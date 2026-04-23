#!/usr/bin/env python3
import os
import re

# Configuration
LANGUAGES_DIR = 'languages'
SOURCE_DIR = '.'
MASTER_LANG = 'en'

def parse_po(file_path):
    entries = []
    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
    current_field = None
    if not os.path.exists(file_path): return []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip('\n')
            if not line.strip():
                if current_entry['msgid'] or current_entry['msgstr']:
                    entries.append(current_entry)
                    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
                current_field = None
                continue
            if line.startswith('#'):
                current_entry['comments'].append(line)
            elif line.startswith('msgid '):
                current_entry['msgid'] = line[7:-1]
                current_field = 'msgid'
            elif line.startswith('msgstr '):
                current_entry['msgstr'] = line[8:-1]
                current_field = 'msgstr'
            elif line.startswith('"'):
                if current_field == 'msgid':
                    current_entry['msgid'] += line[1:-1]
                elif current_field == 'msgstr':
                    current_entry['msgstr'] += line[1:-1]
        if current_entry['msgid'] or current_entry['msgstr']:
            entries.append(current_entry)
    return entries

def save_po(file_path, lang_name, lang_code, keys, translations, fallback_map):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(f'msgid ""\nmsgstr ""\n"Language-Team: {lang_name}\\n"\n"Language: {lang_code}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for key in sorted(keys):
            if not key: continue
            # Priority: Existing translation > Fallback from code > English master string
            val = translations.get(key) or fallback_map.get(key) or key
            f.write(f'msgid "{key}"\nmsgstr "{val.replace("\n", "\\n")}"\n\n')

def sync():
    print("--- Starting Translation Sync ---")
    
    # 1. Scan Source for Used Keys
    used_keys = {} # key -> default_string
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            if file.endswith('.lua'):
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    # Find loc:t("key") or loc:t("key") or "default"
                    matches = re.finditer(r'loc:t\([\"\'](.*?)[\"\']\)(?:\s*or\s*[\"\'](.*?)[\"\'])?', content)
                    for m in matches:
                        used_keys[m.group(1)] = m.group(2) or used_keys.get(m.group(1), "")
                    # Find fallbacks in localization_xray.lua
                    if 'localization_xray.lua' in file:
                        fb_matches = re.finditer(r'(\w+)\s*=\s*\"(.*?)\"', content)
                        for m in fb_matches:
                            used_keys[m.group(1)] = m.group(2)

    print(f"Found {len(used_keys)} keys in source code.")

    # 2. Update English Master
    en_path = os.path.join(LANGUAGES_DIR, f'{MASTER_LANG}.po')
    en_entries = parse_po(en_path)
    en_existing = {e['msgid']: e['msgstr'] for e in en_entries if e['msgid']}
    
    # Merge existing en strings with newly found keys
    en_final = {}
    for key in used_keys:
        en_final[key] = en_existing.get(key) or used_keys[key] or key
    
    save_po(en_path, 'English', 'en', en_final.keys(), en_final, used_keys)
    print(f"Updated {MASTER_LANG}.po")

    # 3. Update Other Languages
    for file in os.listdir(LANGUAGES_DIR):
        if file.endswith('.po') and not file.startswith(MASTER_LANG):
            lang_code = file.split('.')[0]
            path = os.path.join(LANGUAGES_DIR, file)
            entries = parse_po(path)
            
            # Extract Language Name from header
            lang_name = lang_code.capitalize()
            for e in entries:
                if e['msgid'] == '':
                    m = re.search(r'Language-Team: (.*?)\\n', e['msgstr'])
                    if m: lang_name = m.group(1)
            
            existing_tr = {e['msgid']: e['msgstr'] for e in entries if e['msgid'] and e['msgstr']}
            
            # Save with current master keys, keeping existing translations
            save_po(path, lang_name, lang_code, en_final.keys(), existing_tr, en_final)
            
            missing_count = len([k for k in en_final if k not in existing_tr])
            print(f"Updated {file} ({missing_count} keys need translation)")

    print("--- Sync Complete ---")

if __name__ == "__main__":
    sync()
