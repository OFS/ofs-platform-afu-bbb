#!/usr/bin/env python3

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: MIT

"""Generate an ofs_plat_if tree.

After loading a platform configuration .ini file, a platform-specific
ofs_plat_if is constructed. For some releases, this generated interface
may be complete. For others, the generated tree may be the starting point
for further editing either by hand or with platform-specific scripts.

The default values for each type of physical interface are loaded from
the file config/defaults.ini in the source tree. Storing standard values
in a shared configuration file allows platform-specific .ini files to
specify only the subset of values that are non-standard.

The script validates some basic requirements of a configuration .ini file:

  - Section names must be a tuple of <class_name>.<number>. The only exception
    is number 0, which may be omitted.
  - Numbers must be monotonically increasing, starting at 0.
  - Every section must declare a 'native_class', which defines the underlying
    base implementation of the interface to the FIM.
"""

import os
import sys
from collections import OrderedDict

try:
    # Python 3 name
    import configparser
except ImportError:
    # Python 2 name
    import ConfigParser as configparser


class ofs_plat_cfg(object):

    def __init__(self, src=None, ini_file=None, disable=None, quiet=False):
        self.src = src
        self.ini_file = ini_file
        self.quiet = quiet

        if not ini_file:
            self.__errorExit("ini_file must be specified!")
        if not os.path.isfile(ini_file):
            self.__errorExit("File '{0}' not found!".format(ini_file))

        # Load the defaults file
        defaults_file = os.path.join(src, 'config', 'defaults.ini')
        if not os.path.isfile(defaults_file):
            self.__errorExit("File '{0}' not found!".format(defaults_file))

        if not quiet:
            print("Parsing configuration defaults file: {0}".format(
                defaults_file))
        self.defaults = configparser.ConfigParser()
        self.defaults.read(defaults_file)

        # Load the configuration file
        if not quiet:
            print("Parsing configuration file: {0}".format(ini_file))
        self.config = configparser.ConfigParser()
        self.config.read(ini_file)

        # In addition to the incoming "disable" list, each section may have
        # an "enabled_by" value. Generate a list of sections that are not
        # enabled.
        not_enabled = self.__find_disabled_sections()

        # Drop sections we've been told to disable
        if (not disable):
            disable = []
        self.__drop_disabled_sections(set(not_enabled + disable))

        # Are the section names legal?
        self.__validate_section_names()

        # Rewrite state from old .ini files for backward compatibility
        self.__backward_compat_rewrite()

        # Generate final section dictionaries by including defaults
        self.__merge_config_and_defaults()

    def sections(self):
        """Return a list of the configuration file's sections."""
        return sorted(self.config.sections())

    def parse_section_name(self, section):
        """Split a section name into class name string and a group number.
        The group number is 0 if not specified."""

        s = section
        p = s.split('.')
        try:
            # More than one period or class name is empty?
            if (len(p) > 2 or len(p[0]) == 0):
                self.__errorExit("Illegal section name ({0})".format(s))
            c = p[0]
            g = 0
            # Group name or number specified? If numeric, convert the group
            # to int.
            if (len(p) == 2):
                g = int(p[1]) if p[1].isnumeric() else p[1]
        except Exception:
            self.__errorExit("Illegal section name ({0})".format(s))

        return c, g

    def section_native_class(self, section):
        """Return the native_class of a section. In the .ini file it is
        just a standard option, but it is treated specially when passed to
        generator scripts."""

        return self.config.get(section, 'native_class')

    def section_template_class(self, section):
        """Return the template_class of a section. For standard classes,
        such as local memory, the template class is the same as the base
        class. Some platforms with unusual interfaces may start by copying
        generic templates using a "template_class" parameter."""

        if self.config.has_option(section, 'template_class'):
            return self.config.get(section, 'template_class')
        else:
            return None

    def section_import_dir(self, section):
        """Return the path of an import if present in a section. If the
        path is relative to the .ini file then translate it."""

        if self.config.has_option(section, 'import'):
            import_path = self.config.get(section, 'import')
            if os.path.isabs(import_path):
                return import_path
            return os.path.abspath(
                os.path.join(os.path.dirname(self.ini_file), import_path))
        else:
            return None

    def section_instance_noun(self, section):
        """The "instance noun" for a section is the noun used to name
        multiple instances of the class, such as "ports", "banks" or
        "channels". The noun is inferred from parameters associated
        with the section, such as "num_ports" and "num_banks"."""

        return self.instance_noun[section]

    def options(self, section):
        """Return a list of the options within a section."""
        return self.merged_config[section].keys()

    def has_option(self, section, option):
        """Is option defined within the section?"""
        return option in self.merged_config[section]

    def get(self, section, option):
        """Return the value of the option within the section."""
        return self.merged_config[section][option]

    def get_options_dict(self, section):
        """Return a section's entire options dictionary."""
        return self.merged_config[section]

    def __validate_section_names(self):
        """Confirm that section names are legal."""

        # Track section names as they are seen
        secs = dict()

        for s in self.config.sections():
            # Break section name into class and group number.
            c, g = self.parse_section_name(s)

            msg = "Group numbers must be monotonically increasing, " + \
                "starting at 0.\n    Section '" + s + "' is illegal."

            if (c not in secs):
                # First time class is seen. Group number must be 0.
                if (g != 0):
                    self.__errorExit(msg)
            elif (isinstance(g, int) and secs[c] + 1 != g):
                # Group is a number but it isn't incrementing by 1. Non-numeric
                # group names don't have to satisfy this requirement.
                self.__errorExit(msg)

            secs[c] = g

            native_class = self.section_native_class(s)
            if (not native_class):
                msg = "Section '" + s + "' must define a 'native_class'"
                self.__errorExit(msg)

    def __find_disabled_sections(self):
        """Look for the enabled_by keyword in sections and return a list of
        sections that are not enabled and should be removed."""

        # Look for a file holding project macros. The same name as the PIM
        # .ini file but with a '.macros' extension.
        macro_fname = os.path.splitext(self.ini_file)[0] + '.macros'
        project_macros = dict()
        if (os.path.exists(macro_fname)):
            with open(macro_fname, 'r') as f:
                for line in f:
                    # Drop comments
                    line = line.split('#', 1)[0].strip()
                    if not line:
                        continue

                    # Handle macros with and without values
                    line = line.split('=', 1)
                    if (len(line) == 1):
                        project_macros[line[0].strip()] = None
                    else:
                        project_macros[line[0].strip()] = line[1].strip()

        # Walk the configured sections, looking for 'enabled_by' options.
        disable_list = []
        for s in self.config.sections():
            if self.config.has_option(s, 'enabled_by'):
                found = False

                # enabled_by may be a list of macro names, separated by '|'.
                # Any one being set is enable to enable the section.
                for e in self.config.get(s, 'enabled_by').split('|'):
                    e = e.strip()
                    if e and (e in project_macros):
                        found = True
                        break

                if not found:
                    disable_list += [s]

                if not self.quiet:
                    print("  Section {} is {}".format(s,
                          'enabled' if found else 'DISABLED'))

        return disable_list

    def __drop_disabled_sections(self, disable):
        """Drop sections that aren't wanted."""

        if (not disable):
            return

        for s in disable:
            self.config.remove_section(s)

    def __backward_compat_rewrite(self):
        """Rewrite the incoming .ini file for backward compatibility."""

        # For a brief time there was an ifc_classes tree for other/extern
        # that duplicated the functionality of generic/ports. The
        # ifc_classes/other tree has been removed. Map old .ini files with:
        #
        #   [other]
        #   native_class=extern
        #
        # to:
        #
        #   [other]
        #   native_class=ports
        #   template_class=generic_templates
        #   type=ofs_plat_other_extern_if
        #
        if self.config.has_section('other'):
            if self.section_native_class('other') == 'extern':
                if not self.quiet:
                    print("  Mapping [other] from other/extern to "
                          "generate_templates/ports")
                self.config.set('other', 'native_class', 'ports')
                self.config.set('other', 'template_class', 'generic_templates')
                self.config.set('other', 'type', 'ofs_plat_other_extern_if')
                if not self.config.has_option('other', 'num_ports'):
                    self.config.set('other', 'num_ports', '1')

    def __merge_config_and_defaults(self):
        """Generate new dictionaries for each section, incorporating default
        values given the section's native class."""

        self.merged_config = {}
        self.instance_noun = {}

        for s in self.config.sections():
            c, g = self.parse_section_name(s)
            native_class = self.section_native_class(s)

            found_defaults = False
            merged = OrderedDict()

            # Is an implementation-independent defaults section present?
            if (self.defaults.has_section(c)):
                found_defaults = True
                merged.update(OrderedDict(self.defaults.items(c)))

            # Are defaults present for the native class?
            native_def_sect = c + '.' + native_class
            if (self.defaults.has_section(native_def_sect)):
                found_defaults = True
                merged.update(
                    OrderedDict(self.defaults.items(native_def_sect)))
            else:
                native_def_sect = None

            # Incorporate platform-specific parameters
            merged.update(OrderedDict(self.config.items(s)))
            self.merged_config[s] = merged

            # The "instance noun" is the name for an instance of the class,
            # typically "port" or "bank".
            if (native_class != 'none'):
                self.__set_instance_noun(c, native_def_sect, s)
            else:
                self.instance_noun[s] = ''

    def __set_instance_noun(self, default_class, default_sect, s):
        """The "instance noun" is the name for an instance of the class,
        typically "port" or "bank". The noun is inferred from the parameters
        associated with the class."""

        # Record the least-significant level with a parameter indicating
        # the noun. The found name records will be strings with the name
        # of the level, which will be used for error messages if needed.
        self.instance_noun[s] = None
        found = {}
        for noun in ['ports', 'banks', 'channels']:
            flag = 'num_' + noun
            if (self.config.has_option(s, flag)):
                found[noun] = self.ini_file + ':[' + s + ']'
            if (self.defaults.has_option(default_sect, flag)):
                found[noun] = 'defaults.ini:[' + default_sect + ']'
            if (self.defaults.has_option(default_class, flag)):
                found[noun] = 'defaults.ini:[' + default_class + ']'

            if (noun in found):
                # Don't allow multiple nouns
                if (self.instance_noun[s]):
                    self.__errorExit('Class {0} illegaly defines both '
                                     '"num_{1}" ({2}) and '
                                     '"num_{3}" ({4})!'.format(
                                         s,
                                         self.instance_noun[s],
                                         found[self.instance_noun[s]],
                                         noun, found[noun]))

                self.instance_noun[s] = noun

        if (not self.instance_noun[s]):
            self.__errorExit('Class ' + s + ' must define "num_ports", ' +
                             '"num_banks" or "num_channels"!')

    def __errorExit(self, msg):
        sys.stderr.write("\nError in ofs_plat_cfg: " + msg + "\n")
        sys.exit(1)
