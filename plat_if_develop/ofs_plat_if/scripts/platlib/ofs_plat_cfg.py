#!/usr/bin/env python

#
# Copyright (c) 2019, Intel Corporation
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of the Intel Corporation nor the names of its contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

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

    def __init__(self, src=None, ini_file=None, quiet=False):
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

        # Are the section names legal?
        self.__validate_section_names()
        # Generate final section dictionaries by including defaults
        self.__merge_config_and_defaults()

    def sections(self):
        """Return a list of the configuration file's sections."""
        return self.config.sections()

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
            # Group number specified?
            if (len(p) == 2):
                g = int(p[1])
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

    def section_instance_noun(self, section):
        """The "instance noun" for a section is the noun used to name
        multiple instances of the class, such as "ports" or "banks". The
        noun is inferred from parameters associated with the section,
        such as "num_ports" and "num_banks"."""

        return self.instance_noun[section]

    def options(self, section):
        """Return a list of the options within a section."""
        return self.merged_config[section].keys()

    def get(self, section, option):
        """Return the value of the option within the section."""
        return self.merged_config[section][option]

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
            elif (secs[c] + 1 != g):
                # Class seen before but group number isn't incrementing by 1
                self.__errorExit(msg)

            secs[c] = g

            native_class = self.section_native_class(s)
            if (not native_class):
                msg = "Section '" + s + "' must define a 'native_class'"
                self.__errorExit(msg)

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
        found = {}
        for noun in ['ports', 'banks']:
            flag = 'num_' + noun
            if (self.config.has_option(s, flag)):
                found[noun] = self.ini_file + ':[' + s + ']'
            if (self.defaults.has_option(default_sect, flag)):
                found[noun] = 'defaults.ini:[' + default_sect + ']'
            if (self.defaults.has_option(default_class, flag)):
                found[noun] = 'defaults.ini:[' + default_class + ']'

        self.instance_noun[s] = ''
        if ('ports' in found) and ('banks' not in found):
            self.instance_noun[s] = 'ports'
        elif ('ports' not in found) and ('banks' in found):
            self.instance_noun[s] = 'banks'
        elif ('ports' not in found) and ('banks' not in found):
            self.__errorExit('Class ' + s + ' must define either ' +
                             '"num_ports" or "num_banks"!')
        else:
            self.__errorExit('Class ' + s + ' illegaly defines both ' +
                             '"num_ports" (' + found['ports'] + ') and ' +
                             '"num_banks" (' + found['banks'] + ')!')

    def __errorExit(self, msg):
        sys.stderr.write("\nError in ofs_plat_cfg: " + msg + "\n")
        sys.exit(1)
