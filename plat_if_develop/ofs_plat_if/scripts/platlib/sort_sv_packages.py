#!/usr/bin/env python

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
this._re_find_pkg = re.compile('([\\w]+_pkg|[\\w]+_def)::',
                               re.IGNORECASE)
this._re_remove_comments = re.compile('//.*?(\r\n?|\n)|/\\*.*?\\*/',
                                      re.DOTALL)


def sort_pkg_list(pkgs):
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
        pkg_deps[p] = _read_dep_packages(fn)

    # Global _pkgs_visited breaks dependence cycles
    this._pkgs_visited = set()
    sorted_pkg_names = []
    for p in pkg_list:
        sorted_pkg_names = sorted_pkg_names + \
            _dep_first_packages(p, pkg_deps, [])

    # Map back from a list of leaf names to full path names
    sorted_pkgs = []
    for p in sorted_pkg_names:
        sorted_pkgs.append(pkg_path_map[p])

    return sorted_pkgs


def _dep_first_packages(pkg, pkg_deps, cur_pkg_walk):
    """Compute a dependence-order list of packages. Pkg_deps holds the
    set of other packages on which each package depends directly. It
    drives the recursive walk. Cur_pkg_walk is passed down the tree
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
                _dep_first_packages(p, pkg_deps, cur_pkg_walk)

    # Put the current package on the list now that packages on which
    # it depends are listed.
    if (pkg not in this._pkgs_visited):
        this._pkgs_visited.add(pkg)
        sorted_pkg_list = sorted_pkg_list + [pkg]

    return sorted_pkg_list


def _read_dep_packages(filename):
    """Return a set of packages on which filename depends, computed
    by reading the file and looking for package references."""

    text = open(filename, 'r').read()
    text = this._re_remove_comments.sub('', text)
    return set(this._re_find_pkg.findall(text))
