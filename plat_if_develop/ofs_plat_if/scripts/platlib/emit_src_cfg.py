#!/usr/bin/env python

# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: MIT

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
import re
import hashlib


class emit_src_cfg(object):

    def __init__(self, dirs=None, verbose=False,
                 script_name='gen_ofs_plat_if'):
        self.verbose = verbose
        self.script_name = script_name

        # Regular expressions used in the class
        self.re_find_pkg = re.compile('([\\w]+_pkg|[\\w]+_def)::',
                                      re.IGNORECASE)
        self.re_remove_comments = re.compile('//.*?(\r\n?|\n)|/\\*.*?\\*/',
                                             re.DOTALL)

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
            '.svh':  'SYSTEMVERILOG_FILE',
            '.vhd':  'VHDL_FILE',
            '.vhdl': 'VHDL_FILE'
            }

        # Generate a list of all files in the tree
        self.all_files = []
        f_hashes = set()
        # Each e[0] is a directory and e[2] a list of files in the directory
        for e in self.tree:
            for fn in e[2]:
                # Sometimes the same file appears twice, for example from
                # Platform Designer. This can cause simulators to raise errors.
                # Compute the hash of every file to eliminate duplicates.
                fp = os.path.join(e[0], fn)
                sha256 = self.__get_file_sha256(fp)
                if sha256 not in f_hashes:
                    f_hashes.add(sha256)
                    self.all_files.append(fp)

        # Sort packages in dependence order. Simulators and Quartus expect
        # to encounter packages in order.
        self.__sort_packages()

    def include_dirs(self):
        """Return a list of directories that contain header files."""

        return [e[0] for e in self.tree if self.__has_includes(e[2])]

    def __get_file_sha256(self, fpath):
        """Return the SHA-256 of the file at fpath."""
        h = hashlib.sha256()
        with open(fpath, 'rb') as file:
            while True:
                c = file.read(h.block_size)
                if not c:
                    break
                h.update(c)

        return h.hexdigest()

    def __has_includes(self, fnames):
        for fn in fnames:
            if fn.lower().endswith(".vh") or \
               fn.lower().endswith(".svh") or \
               fn.lower().endswith(".h"):
                return True
        return False

    def __sort_packages(self):
        """Sort the list of sources that are packages in dependence order,
        computed by parsing each package and looking for references to
        other packages."""

        # We assume that packages all end in either _pkg.sv or _def.sv.
        pkgs = [fn for fn in self.all_files
                if (fn.lower().endswith("_pkg.sv") or
                    fn.lower().endswith("_def.sv"))]

        # Dictionary mapping package leaf name to path
        pkg_path_map = {}
        # Dictionary mapping package leaf name to packages on which it
        # depends.
        pkg_deps = {}
        # List of package leaf names.
        pkg_list = []
        for fn in pkgs:
            # Drop ".sv" from the key
            p = os.path.basename(fn)
            if (p.lower().endswith(".sv")):
                p = p[:-3]
            pkg_list.append(p)
            pkg_path_map[p] = fn
            pkg_deps[p] = self.__read_dep_packages(fn)

        # Global __pkgs_visited breaks dependence cycles
        self.__pkgs_visited = set()
        sorted_pkg_list = []
        for p in pkg_list:
            sorted_pkg_list = sorted_pkg_list + \
                self.__dep_first_packages(p, pkg_deps, [])

        # Map back from a list of leaf names to full path names
        self.__src_package_list = []
        for p in sorted_pkg_list:
            self.__src_package_list.append(pkg_path_map[p])

    def __dep_first_packages(self, pkg, pkg_deps, cur_pkg_walk):
        """Compute a dependence-order list of packages. Pkg_deps holds the
        set of other packages on which each package depends directly. It
        drives the recursive walk. Cur_pkg_walk is passed down the tree
        and is used to detect cycles in the dependence graph."""

        # Package already visited (and therefore in the list already)?
        if (pkg in self.__pkgs_visited):
            return []

        # Unknown package name. Probably an external reference. Ignore it.
        if (pkg not in pkg_deps):
            return []

        # Is there a cycle in the dependence graph?
        if (pkg in cur_pkg_walk):
            # Get the part of the current walk beginning with the cycle
            cycle_path = cur_pkg_walk[cur_pkg_walk.index(pkg):]
            # Ignore a file that depends on itself since that's strange
            # but sometimes legal. Report everything else.
            if (len(cycle_path) > 1):
                print("  WARNING -- Cycle in package dependence:")
                print("    {}".format(str(cycle_path + [pkg])))
            return []

        # Recursive dependence walk
        cur_pkg_walk = cur_pkg_walk + [pkg]
        sorted_pkg_list = []
        if pkg in pkg_deps:
            for p in pkg_deps[pkg]:
                sorted_pkg_list = sorted_pkg_list + \
                    self.__dep_first_packages(p, pkg_deps, cur_pkg_walk)

        # Put the current package on the list now that packages on which
        # it depends are listed.
        if (pkg not in self.__pkgs_visited):
            self.__pkgs_visited.add(pkg)
            sorted_pkg_list = sorted_pkg_list + [pkg]

        return sorted_pkg_list

    def __read_dep_packages(self, filename):
        """Return a set of packages on which filename depends, computed
        by reading the file and looking for package references."""

        text = open(filename, 'r').read()
        text = self.re_remove_comments.sub('', text)
        return set(self.re_find_pkg.findall(text))

    def src_packages(self):
        """Return a list of all SystemVerilog packages (files matching
        *_pkg.sv or *_def.sv). (The FIM uses _def for some packages.)
        Packages are sorted in dependence order."""

        return self.__src_package_list

    def src_rtl(self):
        """Return a list of all files that are RTL sources."""

        # Generate a list of all source files with suffixes found in
        # self.src_map
        rtl = [fn for fn in self.all_files
               if (os.path.splitext(fn.lower())[1] in self.src_map)]
        # Filter out packages and includes
        return [fn for fn in rtl
                if not fn.lower().endswith("_pkg.sv") and
                not fn.lower().endswith("_def.sv") and
                not fn.lower().endswith(".vh") and
                not fn.lower().endswith(".svh")]

    def is_sim_only(self, fn):
        """Detect simulation-only sources by matching a directory named
        "sim" or files beginning with "sim_" or "ase_"."""

        # Match any case
        fn = fn.lower()
        # Files beginning with "ase_" or "sim_" are simulation only
        base_name = os.path.basename(fn)
        if base_name.startswith("ase_") or base_name.startswith("sim_"):
            return True
        if base_name == "sim":
            return True
        if os.path.basename(os.path.dirname(fn)) == "sim":
            return True
        return False

    def emit_sim_includes(self, dir, fname, is_plat_if=True):
        """Generate the simulator include file (probably
        platform_if_includes.txt)."""

        hdr = """##
## Add OFS Platform Interface include paths.
##
## Generated by """ + self.script_name + """ from ofs-platform-afu-bbb
## repository.
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

+define+RTL_SIMULATION
+define+SIM_MODE
"""

        if (is_plat_if):
            hdr += "+define+PLATFORM_IF_AVAIL\n"
        hdr += "\n"

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

    def emit_sim_sources(self, dir, fname, is_plat_if=True,
                         prefix='platform_if'):
        """Generate the simulator sources file (probably
        platform_if_addenda.txt)."""

        hdr = """##
## Import OFS Platform Interface sources.
##
## Generated by """ + self.script_name + """ from ofs-platform-afu-bbb
## repository.
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

"""

        hdr += "-F " + prefix + "_includes.txt\n\n"

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

    def emit_qsf_sources(self, dir, fname, is_plat_if=True):
        """Generate the Quartus sources file (probably
        platform_if_addenda.qsf)."""

        hdr = """##
## Import OFS Platform Interface sources.
##
## Generated by """ + self.script_name + """ from ofs-platform-afu-bbb
## repository.
##

# Directory of script
set THIS_DIR [file dirname [info script]]

"""

        if (is_plat_if):
            hdr += """# Platform interface is available.
set_global_assignment -name VERILOG_MACRO "PLATFORM_IF_AVAIL=1"
set IS_OFS_AFU [info exists platform_cfg::PLATFORM_PROVIDES_OFS_PLAT_IF]

"""

        tgt = os.path.join(dir, fname)
        if (self.verbose):
            print("  Emitting Quartus sources file: {0}".format(tgt))

        try:
            this_dir = '${THIS_DIR}'
            with open(tgt, "w") as outf:
                outf.write(hdr)

                # Include paths
                for d in self.include_dirs():
                    # Skip ASE-specific sources
                    if self.is_sim_only(d):
                        continue

                    rp = os.path.relpath(d, dir)
                    outf.write('set_global_assignment -name ' +
                               'SEARCH_PATH' +
                               ' "{0}/{1}"\n'.format(this_dir, rp))
                outf.write('\n')

                # Packages
                for f in self.src_packages():
                    rp = os.path.relpath(f, dir)
                    outf.write('set_global_assignment -name ' +
                               'SYSTEMVERILOG_FILE' +
                               ' "{0}/{1}"\n'.format(this_dir, rp))
                outf.write('\n')

                # Now normal sources
                for f in self.src_rtl():
                    # Skip ASE-specific sources
                    if self.is_sim_only(f):
                        continue

                    rp = os.path.relpath(f, dir)
                    # Map suffix to a Quartus type
                    t = self.src_map[os.path.splitext(rp.lower())[1]]
                    outf.write(('set_global_assignment -name {0: <18} ' +
                                '"{1}/{2}"\n').format(t, this_dir, rp))
                outf.write('\n')

                # Timing constraint files
                for f in self.all_files:
                    rp = os.path.relpath(f, dir)
                    if rp.lower().endswith('.sdc'):
                        outf.write('set_global_assignment -name ' +
                                   'SDC_FILE          ' +
                                   ' "{0}/{1}"\n'.format(this_dir, rp))
                outf.write('\n')

                # Tcl files
                for f in self.all_files:
                    rp = os.path.relpath(f, dir)
                    if rp.lower().endswith('.tcl'):
                        outf.write('set_global_assignment -name ' +
                                   'SOURCE_TCL_SCRIPT_FILE' +
                                   ' "{0}/{1}"\n'.format(this_dir, rp))

        except IOError:
            self.__errorExit('Failed to open {0} for writing.'.format(tgt))

    def dump(self, fname):
        """Dump the tree to fname (for debugging)."""

        try:
            with open(fname, 'w') as outf:
                for e in self.tree:
                    outf.write(e[0] + '\n')
                    for f in e[2]:
                        outf.write('  ' + f + '\n')
        except IOError:
            self.__errorExit('Failed to open {0} for writing.'.format(fname))

    def __errorExit(self, msg):
        sys.stderr.write('\nError: ' + msg + '\n')
        sys.exit(1)
