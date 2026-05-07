#!/usr/bin/env python3
import glob
import sys
import os
from luaparser import ast

def check_syntax(directory):
    failed = False
    lua_files = glob.glob(os.path.join(directory, '*.lua'))
    if not lua_files:
        print(f"No .lua files found in {directory}")
        return False

    for f in lua_files:
        try:
            with open(f, encoding='utf-8') as file:
                ast.parse(file.read())
        except Exception as e:
            err_msg = str(e)[:200]
            print(f"SYNTAX ERROR IN {f}: {err_msg}")
            failed = True

    return not failed

if __name__ == "__main__":
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "xray.koplugin"
    if check_syntax(target_dir):
        print(f"ALL FILES IN {target_dir} PASS SYNTAX CHECK")
        sys.exit(0)
    else:
        sys.exit(1)
