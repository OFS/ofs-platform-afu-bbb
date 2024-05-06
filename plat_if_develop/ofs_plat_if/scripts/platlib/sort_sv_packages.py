#!/usr/bin/env python3

# Copyright (C) 2023 Intel Corporation
# SPDX-License-Identifier: MIT

"""SystemVerilog requires packages to be defined in dependence order.
This module provides a sort_pkg_list function that parses a list of
source files and returns a sorted list."""

import os
import sys
import re

this = sys.modules[__name__]

# Regular expressions used when parsing packages
this._re_find_pkg = re.compile('([\\w]+_pkg|[\\w]+_defs?)::',
                               re.IGNORECASE)
this._re_find_inc = re.compile('`include[\\s]+"([.\\w]+)"',
                               re.IGNORECASE)
this._re_remove_comments = re.compile('//.*?(\r\n?|\n)|/\\*.*?\\*/',
                                      re.DOTALL)

# This matches a pattern that can be used to flag a region
# to ignore in a file. Everything between
#   // PKG_SORT_IGNORE_START
# and
#   // PKG_SORT_IGNORE_END
# is ignored.
this._re_pkg_sort_ignore = \
    re.compile('// *PKG_SORT_IGNORE_START.*?// *PKG_SORT_IGNORE_END',
               re.MULTILINE | re.DOTALL)


class CircularPkgDependence(Exception):
    """Raised when a package dependence chain is circular."""
    pass


def sort_pkg_list(pkgs, inc_dirs):
    """Sort the list of SystemVerilog packages in dependence order,
    computed by parsing each package and looking for references to
    other packages."""

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
        # Read the package and find references to other packages.
        # Also discover and read include files, looking for package
        # references there.
        pkg_deps[p] = _read_dep_packages(fn, inc_dirs)

    # Global _pkgs_visited breaks dependence cycles
    this._pkgs_visited = set()
    sorted_pkg_names = []
    for p in pkg_list:
        sorted_pkg_names = sorted_pkg_names + \
            _dep_first_packages(p, pkg_deps, [], [])

    # Map back from a list of leaf names to full path names
    sorted_pkgs = []
    for p in sorted_pkg_names:
        sorted_pkgs.append(pkg_path_map[p])

    return sorted_pkgs


def _dep_first_packages(pkg, pkg_deps, cur_pkg_walk, cur_pkg_incs):
    """Compute a dependence-order list of packages. Pkg_deps holds the
    collection of other packages on which each package depends directly.
    It drives the recursive walk. cur_pkg_walk is passed down the tree
    and is used to detect cycles in the dependence graph."""

    # Package already visited (and therefore in the list already)?
    if (pkg in this._pkgs_visited):
        return []

    # Unknown package name. Probably an external reference. Ignore it.
    if (pkg not in pkg_deps):
        return []

    # Is there a cycle in the dependence graph?
    if (pkg in cur_pkg_walk):
        # Get the part of the current walk beginning with the cycle
        cycle_start_idx = cur_pkg_walk.index(pkg)
        cycle_path = cur_pkg_walk[cycle_start_idx:]
        # cur_pkg_incs is the same length as cur_pkg_walk. For each
        # entry, it indicates the include file chain through which
        # the dependence was found.
        cycle_incs = cur_pkg_incs[cycle_start_idx:]

        # Ignore a file that depends on itself since that's strange
        # but sometimes legal. Report everything else.
        if (len(cycle_path) > 1):
            # Currently only a warning. This should probably be
            # an error.
            sys.stderr.write("  ERROR -- Cycle in package dependence:\n")
            for i, p in enumerate(cycle_path):
                chain = [p]
                if cycle_incs[i]:
                    chain += cycle_incs[i]
                sys.stderr.write('    {} ->\n'.format(' -> '.join(chain)))
            sys.stderr.write('    {}\n'.format(pkg))

            _circular_error_msg()

            raise CircularPkgDependence
        return []

    # Recursive dependence walk
    sorted_pkg_list = []
    if pkg in pkg_deps:
        for p, d in pkg_deps[pkg].items():
            sorted_pkg_list = sorted_pkg_list + \
                _dep_first_packages(p, pkg_deps,
                                    cur_pkg_walk + [pkg],
                                    cur_pkg_incs + [d])

    # Put the current package on the list now that packages on which
    # it depends are listed.
    if (pkg not in this._pkgs_visited):
        this._pkgs_visited.add(pkg)
        sorted_pkg_list = sorted_pkg_list + [pkg]

    return sorted_pkg_list


def _read_dep_packages(filename, inc_dirs):
    """Return a dictionary of packages on which filename depends,
    computed by reading the file and looking for package references.
    The dictionary indicates whether the dependence was found
    as a direct reference or through a chain of include files.

    inc_dirs is the collection of all directories that should be
    searched for include files."""

    try:
        text = open(filename, 'r').read()
    except UnicodeDecodeError:
        print('read_dep_packages: Ignoring binary file {}'.format(filename))
        return {}

    text = this._re_pkg_sort_ignore.sub('', text)
    text = this._re_remove_comments.sub('', text)

    # Store references to other packages as a dictionary. Direct
    # references have a value of None. Chains through include,
    # calculated next, will have the name of the include file.
    dep_pkgs = {}
    for d in this._re_find_pkg.findall(text):
        dep_pkgs[d] = None

    for inc_fname in this._re_find_inc.findall(text):
        deps = _read_inc_packages(inc_fname, set(), inc_dirs)
        for d, chain in deps.items():
            if d not in dep_pkgs:
                dep_pkgs[d] = chain

    return dep_pkgs


def _read_inc_packages(fname, inc_visited, inc_dirs):
    """Recursively parse include files, looking for package references.
    The inc_visited set tracks include files already visited.

    NOTE: The parser here only looks for tokens. It does not understand
    that macros may not be used, nor does it understand `ifdef and
    conditional compilation. Only very simple package dependence
    patterns are supported."""

    # Already parsed this include file?
    if fname in inc_visited:
        return {}
    inc_visited |= {fname}

    # Look for include file fname
    fpath = _find_inc_path(fname, inc_dirs)
    # Ignore files outside the search path
    if not fpath:
        return {}

    text = open(fpath, 'r').read()
    text = this._re_pkg_sort_ignore.sub('', text)
    text = this._re_remove_comments.sub('', text)

    # dep_pkgs dictionary entries store packages as keys and
    # the include file chain in the values as lists.
    dep_pkgs = {}
    for d in this._re_find_pkg.findall(text):
        dep_pkgs[d] = [fname]

    # Recursive parse of this include file's includes.
    for inc_fname in this._re_find_inc.findall(text):
        deps = _read_inc_packages(inc_fname, inc_visited, inc_dirs)
        for d, chain in deps.items():
            if d not in dep_pkgs:
                # The full include file chain is the current file plus
                # the chain returned by the recursion.
                dep_pkgs[d] = [fname] + chain

    return dep_pkgs


def _find_inc_path(inc_fname, inc_dirs):
    """Find an include file by searching include directories."""

    for d in inc_dirs:
        fpath = os.path.join(d, inc_fname)
        if os.path.isfile(fpath):
            return fpath

    return None


def _circular_error_msg():
    sys.stderr.write("""
The package sorter uses a very simple parser. Any text in a file that
looks like a package reference adds a dependence edge. This is true of
macro definitions, even when they are not referenced, and conditional
code that should be eliminated by a preprocessor. As a result, the
sorter may see a dependence cycle (a file that ultimately depends on
itself) when there is no actual dependence.

To work around this, a comment can be added to source files to force
the sorter to ignore a block of text. False package dependence can
often be eliminated by wrapping macro definitions or entire include
directives between PKG_SORT_IGNORE_START and PKG_SORT_IGNORE_END.
For an example, see:
    https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/ofs_plat_if.vh
""")
