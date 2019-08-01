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

"""Walk a directory tree and find source files in order to construct and
emit Quartus and simulator configuration files that load the modules
in the generated ofs_plat_if tree. The configuration is generated
dynamically, since the set of RTL sources in a generated ofs_plat_if
depends on the platform's native interfaces.

For some platforms, the source listing may just be a starting point before
the tree is edited either by hand or updated with platform-specific
scripts."""

import os
import sys


class emit_src_cfg(object):

    def __init__(self, dirs=None, verbose=False):
        self.verbose = verbose

        #
        # Save a sorted list of breadth first walk of the directory hierarchy.
        # Adding the -(depth count) as the first entry in dirlist causes the
        # sort to return the deepest part of the hierarchy first.
        #
        # We use a breadth first walk under the assumption that package
        # dependence is top-down.
        #
        t = []
        for d in dirs:
            dirlist = \
                ((-dpath.count(os.path.sep), dpath, dnames, filenames) for
                 dpath, dnames, filenames in os.walk(d, topdown=False))
            # Sort by depth. Also sort names within a directory.
            t = t + [[e[1], sorted(e[2]), sorted(e[3])] for e in
                     sorted(dirlist)]

        # Tree is the list of directories in the target tree, sorted first by
        # depth and then by name. Each entry in the list is a 3 element list:
        #   1. The directory path
        #   2. A sorted list of all sub-directories contained in (1)
        #   3. A sorted list of all files contained in (1)
        self.tree = t

        self.src_map = {
            '.sv':   'SYSTEMVERILOG_FILE',
            '.v':    'VERILOG_FILE',
            '.vh':   'SYSTEMVERILOG_FILE',
            '.vhd':  'VHDL_FILE',
            '.vhdl': 'VHDL_FILE'
            }

        # Generate a list of all files in the tree
        self.all_files = []
        # Each e[0] is a directory and e[2] a list of files in the directory
        for e in self.tree:
            for fn in e[2]:
                self.all_files.append(os.path.join(e[0], fn))

    def include_dirs(self):
        """Return a list of directories that contain header files."""

        return [e[0] for e in self.tree if self.__has_includes(e[2])]

    def __has_includes(self, fnames):
        for fn in fnames:
            if fn.lower().endswith(".vh") or fn.lower().endswith(".h"):
                return True
        return False

    def src_packages(self):
        """Return a list of all SystemVerilog packages (files matching
        *_pkg.sv)."""

        return [fn for fn in self.all_files if fn.lower().endswith("_pkg.sv")]

    def src_rtl(self):
        """Return a list of all files that are RTL sources."""

        # Generate a list of all source files with suffixes found in
        # self.src_map
        rtl = [fn for fn in self.all_files
               if (os.path.splitext(fn.lower())[1] in self.src_map)]
        # Filter out packages and includes
        return [fn for fn in rtl
                if not fn.lower().endswith("_pkg.sv") and
                not fn.lower().endswith(".vh")]

    def emit_sim_includes(self, dir, fname):
        """Generate the simulator include file (probably
        platform_if_includes.txt)."""

        hdr = """##
## Add OFS Platform Interface include paths.
##
## Generated by gen_ofs_plat_if from ofs-platform-afu-bbb repository.
##
## Include this file in an ASE build to import platform interface definitions
## into a simulation environment by adding the following line to
## vlog_files.list in an ASE build directory:
##
##     -F <absolute path to this directory>/""" + fname + """
##
## Note that "-F" must be used and not "-f".  The former uses paths relative
## to this directory.  The latter uses only absolute paths.
##

+define+PLATFORM_IF_AVAIL
+define+RTL_SIMULATION

"""

        tgt = os.path.join(dir, fname)
        if (self.verbose):
            print("  Emitting simulator include file: {0}".format(tgt))

        try:
            with open(tgt, "w") as outf:
                outf.write(hdr)
                for d in self.include_dirs():
                    rp = os.path.relpath(d, dir)
                    outf.write("+incdir+{0}\n".format(rp))
        except IOError:
            self.__errorExit("Failed to open {0} for writing.".format(tgt))

    def emit_sim_sources(self, dir, fname):
        """Generate the simulator sources file (probably
        platform_if_addenda.txt)."""

        hdr = """##
## Import OFS Platform Interface sources.
##
## Generated by gen_ofs_plat_if from ofs-platform-afu-bbb repository.
##
## Include this file in an ASE build to import platform interface definitions
## into a simulation environment by adding the following line to
## vlog_files.list in an ASE build directory:
##
##     -F <absolute path to this directory>/""" + fname + """
##
## Note that "-F" must be used and not "-f".  The former uses paths relative
## to this directory.  The latter uses only absolute paths.
##

-F platform_if_includes.txt

"""

        tgt = os.path.join(dir, fname)
        if (self.verbose):
            print("  Emitting simulator sources file: {0}".format(tgt))

        try:
            with open(tgt, "w") as outf:
                outf.write(hdr)

                # Start with packages
                for f in self.src_packages():
                    rp = os.path.relpath(f, dir)
                    outf.write("{0}\n".format(rp))
                outf.write("\n")

                # Now normal sources
                for f in self.src_rtl():
                    rp = os.path.relpath(f, dir)
                    outf.write("{0}\n".format(rp))

        except IOError:
            self.__errorExit("Failed to open {0} for writing.".format(tgt))

    def emit_qsf_sources(self, dir, fname, ofs_plat_path):
        """Generate the Quartus sources file (probably
        platform_if_addenda.qsf)."""

        hdr = """##
## Import OFS Platform Interface sources.
##
## Generated by gen_ofs_plat_if from ofs-platform-afu-bbb repository.
##

set OFS_PLAT_IF \"""" + ofs_plat_path + """\"

# Platform interface is available.
set_global_assignment -name VERILOG_MACRO "PLATFORM_IF_AVAIL=1"
set IS_OFS_AFU [info exists platform_cfg::PLATFORM_PROVIDES_OFS_PLAT_IF]

"""

        tgt = os.path.join(dir, fname)
        if (self.verbose):
            print("  Emitting Quartus sources file: {0}".format(tgt))

        try:
            with open(tgt, "w") as outf:
                outf.write(hdr)

                # Include paths
                for d in self.include_dirs():
                    rp = os.path.relpath(d, dir)
                    outf.write("set_global_assignment -name " +
                               "SEARCH_PATH" +
                               " $OFS_PLAT_IF/{0}\n".format(rp))
                outf.write("\n")

                # Packages
                for f in self.src_packages():
                    rp = os.path.relpath(f, dir)
                    outf.write("set_global_assignment -name " +
                               "SYSTEMVERILOG_FILE" +
                               " $OFS_PLAT_IF/{0}\n".format(rp))
                outf.write("\n")

                # Now normal sources
                for f in self.src_rtl():
                    rp = os.path.relpath(f, dir)
                    if os.path.basename(rp).lower().startswith("ase_"):
                        # Skip ASE-specific sources
                        continue

                    # Map suffix to a Quartus type
                    t = self.src_map[os.path.splitext(rp.lower())[1]]
                    outf.write(("set_global_assignment -name {0: <18} " +
                                "$OFS_PLAT_IF/{1}\n").format(t, rp))
                outf.write("\n")

                # Timing constraint files
                for f in self.all_files:
                    rp = os.path.relpath(f, dir)
                    if rp.lower().endswith(".sdc"):
                        outf.write("set_global_assignment -name " +
                                   "SDC_FILE          " +
                                   " $OFS_PLAT_IF/{0}\n".format(rp))
                outf.write("\n")

                # Tcl files
                for f in self.all_files:
                    rp = os.path.relpath(f, dir)
                    if rp.lower().endswith(".tcl"):
                        outf.write("set_global_assignment -name " +
                                   "SOURCE_TCL_SCRIPT_FILE" +
                                   " $OFS_PLAT_IF/{0}\n".format(rp))

        except IOError:
            self.__errorExit("Failed to open {0} for writing.".format(tgt))

    def dump(self, fname):
        """Dump the tree to fname (for debugging)."""

        try:
            with open(fname, "w") as outf:
                for e in self.tree:
                    outf.write(e[0] + "\n")
                    for f in e[2]:
                        outf.write("  " + f + "\n")
        except IOError:
            self.__errorExit("Failed to open {0} for writing.".format(fname))

    def __errorExit(self, msg):
        sys.stderr.write("\nError: " + msg + "\n")
        sys.exit(1)
