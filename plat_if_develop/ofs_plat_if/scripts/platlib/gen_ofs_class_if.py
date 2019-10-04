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

"""A collection of functions for generating the platform-specific
portion of an ofs_plat_if tree."""

import os
import sys
import fnmatch
import re
from distutils import dir_util, file_util


def copy_class(src=None, tgt=None, base_class=None, native_class=None,
               params=dict(), group_num=0, verbose=False):
    """Copy the implementation of a single interface class to the target.
    base_class is the type of the interface abstraction, e.g. host_chan.
    native_class is the platform-specific type of the base_class's
    interface, e.g. native_ccip. The params dictionary defines the group-
    specific values of the class configuration, typically loaded from the
    .ini file defining the platform."""

    if (native_class == 'none'):
        if (verbose):
            print('Generating {0} group {1} (no source)'.format(base_class,
                                                                group_num))
        return None

    if (verbose):
        print('Generating {0} group {1} using {2}:'.format(base_class,
                                                           group_num,
                                                           native_class))

    # Source path
    src_subdir = os.path.join('rtl', base_class, native_class)
    if (not os.path.isdir(os.path.join(src, src_subdir))):
        __errorExit('Failed to find source directory: {0}'.format(
            os.path.join(src, src_subdir)))

    # Target path drops the class, since an interface has exactly one class.
    # The platform configuration file picked one class from the available
    # options in the source path.
    tgt_subdir = os.path.join('rtl', base_class)

    if (verbose):
        print('  Copying source {0} to {1}'.format(
            src_subdir, os.path.join(tgt, tgt_subdir)))
    dir_util.copy_tree(os.path.join(src, src_subdir),
                       os.path.join(tgt, tgt_subdir))

    # Is there also an afu_ifcs tree? If yes, merge it into the target
    src_afu_ifc_subdir = os.path.join('rtl', base_class, 'afu_ifcs')
    tgt_afu_ifc_subdir = os.path.join(tgt_subdir, 'afu_ifcs')
    if (os.path.isdir(os.path.join(src, src_afu_ifc_subdir))):
        if (verbose):
            print('    Merging AFU interface sources {0}'.format(
                src_afu_ifc_subdir, os.path.join(tgt, tgt_afu_ifc_subdir)))
        dir_util.copy_tree(os.path.join(src, src_afu_ifc_subdir),
                           os.path.join(tgt, tgt_afu_ifc_subdir))


def use_class_templates(tgt=None, base_class=None, group_num=0,
                        verbose=False):
    """Move the class's group-specific template files to their proper names
    and update the contents to match the names."""

    # What is the target group name? Group 0 is a special case. It is empty.
    group_str = '' if (group_num == 0) else '_g{0}'.format(group_num)

    # Template files with names containing _GROUP_ were copied to
    # the target. Find them, use them to generate group-specific
    # versions, and delete the copied templates.
    dir = os.path.join(tgt, 'rtl', base_class)
    for dirpath, dirnames, filenames in os.walk(dir):
        for fn in fnmatch.filter(filenames, '*_GROUP_*'):
            # Skip backup files
            if (fn[-1] == '~'):
                continue

            tgt_fn = fn.replace('_GROUP', group_str)
            if (verbose):
                print('  Generating {0} from {1}'.format(tgt_fn, fn))

            __gen_file_from_template(os.path.join(dirpath, fn),
                                     os.path.join(dirpath, tgt_fn),
                                     '_GROUP', group_str)
            __note_gen_file(base_class, dir, tgt_fn)
            os.remove(os.path.join(dirpath, fn))


def __gen_file_from_template(src_fn, tgt_fn, src_pattern, tgt_pattern):
    """Copy src_fn to tgt_fn, replacing all instances of src_pattern inside
    the file with tgt_pattern."""

    # Try to be clever about the case of tgt_pattern. We assume that the target
    # should be upper case if the character immediatly preceding the source
    # pattern is upper case.
    upcase_pattern = re.compile(r'([A-Z])' + src_pattern)
    tgt_pattern_upper = r'\1' + tgt_pattern.upper()

    # Drop lines beginning with '//='. These are comments for platform
    # developers in the source files here but are dropped in the generated
    # files.
    src_comment_pattern = re.compile(r'\s*//=')

    s = open(src_fn, 'r')
    t = open(tgt_fn, 'w')

    for line in s:
        # Drop source-only comments?
        if (src_comment_pattern.match(line)):
            continue

        # First do upper case substitution
        line = upcase_pattern.sub(tgt_pattern_upper, line)
        # Now lower case and write out the result
        t.write(line.replace(src_pattern, tgt_pattern))

    s.close()
    t.close()


def __note_gen_file(base_class, dirpath, fn):
    """Called for each file generated from a template."""

    # Add include files to a wrapper include file with a well known name
    if (fn.lower().endswith('.vh')):
        wrapper_fn = 'ofs_plat_{0}_wrapper.vh'.format(base_class)
        wrapper_path = os.path.join(dirpath, wrapper_fn)
        w = __get_wrapper_include_file(wrapper_path)
        w.write('`include "' + fn + '"\n')
        w.close()


def __get_wrapper_include_file(wrapper_path):
    """Create include file if it doesn't exist and return a handle."""

    # Does the file exist already? If so, just open for append.
    if (os.path.exists(wrapper_path)):
        return open(wrapper_path, 'w+')

    # Create the file and add a header
    w = open(wrapper_path, 'w')
    w.write('//\n')
    w.write('// Import all generated headers in this class\n')
    w.write('//\n')
    w.write('// Generated by gen_ofs_plat_if (gen_ofs_class_if)\n')
    w.write('//\n\n')
    return w


def __errorExit(msg):
    sys.stderr.write(msg)
    sys.exit(1)
