#!/usr/bin/env python

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: MIT

"""Copy and transform OFS platform interface template files.

The ofs_template class generates platform-specific RTL by replacing keywords
in template files with platform-specific data structures.
"""

import os
import sys
import re

from .ofs_plat_cfg import ofs_plat_cfg

try:
    # Python 3 name
    import configparser
except ImportError:
    # Python 2 name
    import ConfigParser as configparser


class ofs_template(object):

    def __init__(self, plat_cfg=None, verbose=False):
        """Construct a template file parser. plat_cfg must be an instance of
        ofs_plat_cfg()."""

        self.plat_cfg = plat_cfg
        self.verbose = verbose

        if (not isinstance(plat_cfg, ofs_plat_cfg)):
            self.__errorExit("plat_cfg must be an ofs_plat_cfg() instance!")

    def copy_template_file(self, src_fn, tgt_fn):
        """Copy a template file from src_fn to tgt_fn, replacing template
        variables with platform-specific content."""

        if (self.verbose):
            print("  Generating {0}".format(tgt_fn))

        s = open(src_fn, 'r')
        t = open(tgt_fn, 'w')
        self.__parse_template_file(s, t)
        s.close()
        t.close()

    def __parse_template_file(self, src, tgt):
        """Read from src file descriptor, transform template macros, and write
        the result to the tgt file descriptor."""

        in_template = False
        all_sections = False
        template = ''

        # The template keyword is typically @OFS_PLAT_IF_TEMPLATE@.
        # It may have a suffix the modifies the behavior, currently only
        # ALL (@OFS_PLAT_IF_TEMPLATE_ALL@). When ALL is specified, even
        # .ini sections that have no ports or banks are emitted.
        template_re = re.compile(r'@OFS_PLAT_IF_TEMPLATE([_A-Z]*)@')

        for line in src:
            # Remove template comments (text following "//==")
            if ('//==' in line):
                # Drop entire line?
                if (line.strip()[:4] == '//=='):
                    continue
                # Drop everything following //=
                line = re.sub(r'//==.*', '', line).rstrip() + '\n'

            # Look for @OFS_PLAT_IF_TEMPLATE@ keyword
            match = template_re.search(line)
            if (match):
                if (not in_template):
                    # Starting a new template region
                    in_template = True
                    template = ''
                    # Did the template keyword specify ALL sections
                    # using @OFS_PLAT_IF_TEMPLATE_ALL@?
                    all_sections = (match.group(1) == '_ALL')
                    continue

                # End of template region. Emit the platform-specific
                # code for each interface class and group, using the
                # template.
                in_template = False
                tgt.write(self.__process_template(template, all_sections))
                continue

            if (in_template):
                # Reading a template region. Just collect it and continue.
                template = template + line
                continue

            # Normal line
            tgt.write(line)

        if (in_template):
            self.__errorExit(
                "{0} has unterminated @OFS_PLAT_IF_TEMPLATE@!".format(src))

    def __process_template(self, template, all_sections):
        """Generate platform-specific code by processing the supplied template,
        emitting an instance for each top-level interface class and group.
        Normally, sections with no ports or banks are not emitted. When
        "all_sections" is set these sections are also emitted."""

        str = ''

        # Sections in the .ini file dictate top-level types
        for s in self.plat_cfg.sections():
            # What is an instance of the class called? (E.g. ports or banks)
            noun = self.plat_cfg.section_instance_noun(s)
            # If the noun is empty then skip the section unless all sections
            # are requested.
            if (not noun and not all_sections):
                continue

            # Section name to class/group
            c, g = self.plat_cfg.parse_section_name(s)
            # Change group to a string and make it empty if the group number
            # is zero.
            if (g):
                g = '_g{0}'.format(g)
            else:
                g = ''

            # Substitute @class@ and @group@ in the template. These are case
            # sensitive.
            t = template.replace('@class@', c)
            t = t.replace('@group@', g)
            # Upper case equivalent
            t = t.replace('@CLASS@', c.upper())
            t = t.replace('@GROUP@', g.upper())

            # Instance noun replacement (e.g. "ports" or "banks")
            t = t.replace('@noun@', noun)
            t = t.replace('@NOUN@', noun.upper())

            # @CONFIG_DEFS@ is a large section, emitting preprocessor
            # macros with all configuration state.
            if (t.find('@CONFIG_DEFS@') != -1):
                t = t.replace('@CONFIG_DEFS@',
                              self.__config_defs(s, c.upper() + g.upper()))

            str += t

        return str

    def __config_defs(self, section, section_prefix):
        """Generate the Verilog preprocessor macro configuration variables for
        the section."""

        # Special case when native_class is 'none'. Leave it blank.
        native_class = self.plat_cfg.section_native_class(section)
        native_class_str = ' (' + native_class + ')'
        if (native_class_str == ' (none)'):
            native_class_str = ''

        str = '''
// ========================================================================
//
//  {0}{1} interface parameters
//
// ========================================================================

'''.format(section, native_class_str)

        if (native_class_str != '' and section_prefix != 'DEFINE'):
            str += '`define OFS_PLAT_PARAM_{0}_IS_{1} 1\n'.format(
                section_prefix, native_class.upper())

        for opt in self.plat_cfg.options(section):
            if (opt == 'native_class' and native_class_str == ''):
                # Don't emit NATIVE_CLASS macro when it's empty
                None
            elif (section_prefix == 'DEFINE'):
                # Special case the macro definintion section.
                # Don't apply the OFS_PLAT_PARAM prefix.
                str += '`define {0} {1}\n'.format(
                    opt.upper(), self.plat_cfg.get(section, opt))
            else:
                # Normal case
                val = self.plat_cfg.get(section, opt)

                # Should the value be quoted?
                if (val[0] != '"'):
                    if (opt in ['import', 'native_class']):
                        val = '"{0}"'.format(val)

                str += '`define OFS_PLAT_PARAM_{0}_{1} {2}\n'.format(
                    section_prefix,
                    opt.upper(), val)

                # Expose gaskets as macros that can be tested with ifdef
                if (opt == 'gasket'):
                    str += '`define OFS_PLAT_PARAM_{0}_{1}_IS_{2}\n'.format(
                        section_prefix,
                        opt.upper(), val.upper())

        return str

    def __errorExit(self, msg):
        sys.stderr.write("\nError in ofs_template: " + msg + "\n")
        sys.exit(1)
