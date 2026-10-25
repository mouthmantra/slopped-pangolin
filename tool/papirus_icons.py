#!/usr/bin/env python3
# Copyright 2026 The dahliaOS Authors
# SPDX-License-Identifier: Apache-2.0
"""Copies the Papirus icons Files uses into apps/assets/papirus.

usage: tool/papirus_icons.py PAPIRUS_CHECKOUT [COMMIT]

Files (and only Files) draws files and folders with Papirus
(github.com/PapirusDevelopmentTeam/papirus-icon-theme, GPL-3.0), its
folders in the beige "palebrown" colour (roadmap 5.1). From a checkout with
at least Papirus/{24x24,64x64}/{mimetypes,places} and LICENSE, this copies
the file-type icons and the palebrown folders of both sizes. Symbolic links
become entries of index.json (name -> file) instead of copies; links out of
those folders (to app icons) are left out, so their names fall back to
generic icons.
"""

import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "apps", "assets", "papirus")
SIZES = {"24": "24x24", "64": "64x64"}


def wanted(context, name):
    if context == "mimetypes":
        return True
    return name.startswith("folder-palebrown") or name.startswith("user-palebrown")


def resolve(directory, name, seen=()):
    """The real file behind NAME in DIRECTORY, or None if it leads out."""
    path = os.path.join(directory, name)
    if not os.path.islink(path):
        return name if os.path.isfile(path) else None
    target = os.readlink(path)
    if "/" in target or target in seen:
        return None
    return resolve(directory, target, seen + (name,))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    papirus = sys.argv[1]
    commit = sys.argv[2] if len(sys.argv) > 2 else "unknown"
    shutil.rmtree(OUT, ignore_errors=True)
    index = {}
    for size, folder in SIZES.items():
        for context in ("mimetypes", "places"):
            source = os.path.join(papirus, "Papirus", folder, context)
            target = os.path.join(OUT, size, context)
            os.makedirs(target)
            entries = {}
            for name in sorted(os.listdir(source)):
                if not name.endswith(".svg") or not wanted(context, name):
                    continue
                real = resolve(source, name)
                if real is None or not wanted(context, real):
                    continue
                if not os.path.exists(os.path.join(target, real)):
                    shutil.copyfile(os.path.join(source, real), os.path.join(target, real))
                entries[name[:-4]] = real[:-4]
            index.setdefault(context, {})[size] = entries
    with open(os.path.join(OUT, "index.json"), "w") as f:
        json.dump(index, f, separators=(",", ":"), sort_keys=True)
    shutil.copyfile(os.path.join(papirus, "LICENSE"), os.path.join(OUT, "LICENSE"))
    with open(os.path.join(OUT, "README.md"), "w") as f:
        f.write(
            "Icons from Papirus (https://github.com/PapirusDevelopmentTeam/papirus-icon-theme),\n"
            f"commit {commit}, licensed under the GNU GPL version 3 (LICENSE).\n\n"
            "Only Files uses them: file types and the palebrown (beige) folders, at\n"
            "24 and 64 px. Regenerate with tool/papirus_icons.py.\n"
        )
    files = sum(len(fs) for fs in os.walk(OUT) for fs in [fs[2]])
    print(f"{files} files in {OUT}")


if __name__ == "__main__":
    main()
