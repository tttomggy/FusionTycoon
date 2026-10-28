#!/usr/bin/env python3
"""Compile every .lua under src/ with the real Luau compiler (luau-compile).

luau-lsp analyze does NOT catch compiler limits: "Out of local registers"
(more than 200 locals live in one function, the top level of a module
included), "Out of upvalues", too many constants, etc. Roblox refuses to
load such a module, and every module that requires it dies with "Requested
module experienced an error while loading" (HudController at 1bc04bb took
18 selftest checks and most of the client down with it).

Usage: python3 tools/compile_check.py [path/to/luau-compile]
Get luau-compile from https://github.com/luau-lang/luau/releases
(luau-ubuntu.zip / luau-windows.zip / luau-macos.zip). Exits non-zero on
any compile error. Run it next to the parser and theme_token_check.py
before every push.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")


def main() -> int:
    exe = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau-compile")
    if not exe:
        print("luau-compile not found: pass its path or put it on PATH (see this file's header)")
        return 2
    failures = 0
    count = 0
    for folder, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith(".lua"):
                continue
            path = os.path.join(folder, name)
            count += 1
            run = subprocess.run([exe, "--binary", path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if run.returncode != 0 or run.stderr.strip():
                failures += 1
                print(os.path.relpath(path, os.path.join(ROOT, "..")) + ": " + run.stderr.strip().splitlines()[0])
    print(f"compile_check: {count} files, {failures} with compile errors")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
