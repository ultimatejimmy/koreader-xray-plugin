#!/usr/bin/env python3
import os
import re
import sys

# Configuration
LANGUAGES_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin', 'languages')
SOURCE_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin')

def parse_po_keys(file_path):
    keys = set()
    if not os.path.exists(file_path): return keys
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            m = re.match(r'^msgid "(.*)"$', line.strip())
            if m and m.group(1):
                keys.add(m.group(1))
    return keys

def check_translations():
    print("--- Checking Translation Sync Status ---")
    
    # 1. Scan Source for Used Keys
    used_keys = set()
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            if file.endswith('.lua'):
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    # Find loc:t("key")
                    matches = re.finditer(r'loc:t\([\"\']([^\"\']*)[\"\']', content)
                    for m in matches:
                        used_keys.add(m.group(1))
                    # Find fallbacks in localization_xray.lua
                    if 'localization_xray.lua' in file:
                        fb_matches = re.finditer(r'(\w+)\s*=\s*\"', content)
                        for m in fb_matches:
                            used_keys.add(m.group(1))

    print(f"Detected {len(used_keys)} keys in source code.")

    # 2. Check each .po file
    failed = False
    po_files = [f for f in os.listdir(LANGUAGES_DIR) if f.endswith('.po')]
    
    for file in po_files:
        path = os.path.join(LANGUAGES_DIR, file)
        existing_keys = parse_po_keys(path)
        
        missing = used_keys - existing_keys
        if missing:
            print(f"FAILED: {file} is missing {len(missing)} keys:")
            for k in sorted(list(missing)):
                print(f"  - {k}")
            failed = True
        else:
            print(f"PASSED: {file} is in sync.")

    if failed:
        print("\nError: Translation files are out of sync with source code.")
        print("Run 'python tools/sync_translations.py' to fix this.")
        sys.exit(1)
    
    print("\nAll translation files are correctly synchronized!")
    sys.exit(0)

if __name__ == "__main__":
    check_translations()
