#!/usr/bin/env python3
import os
import re
import sys
import sync_translations

# UTF-8 stdout/stderr reconfiguration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

PLUGIN_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin'))
LANGUAGES_DIR = os.path.join(PLUGIN_DIR, 'languages')
SOURCE_DIR = PLUGIN_DIR

LANG_NAMES = {
    'ar': 'Arabic',
    'de': 'German',
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'hu': 'Hungarian',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'nl': 'Dutch',
    'pl': 'Polish',
    'pt_br': 'Portuguese (Brazil)',
    'ru': 'Russian',
    'sr': 'Serbian',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'zh_CN': 'Simplified Chinese',
}

UI_WIDGET_PATTERNS = [
    r'TextWidget:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'TextBoxWidget:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'Button:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'InputDialog:new\s*\{[^}]*?title\s*=\s*"([^"]+)"',
    r'InputDialog:new\s*\{[^}]*?description\s*=\s*"([^"]+)"',
    r'InfoMessage:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'ConfirmBox:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
]

TRANSLATION_MAX_LENGTHS = {
    'Restart Now': 16,
    'Later': 12,
}

ENCODING_SENSITIVE_KEYS = {
    'progress_please_wait',
}

def decode_po_string(s):
    if hasattr(sync_translations, 'decode_po_string'):
        return sync_translations.decode_po_string(s)
    return s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\') if s else ""

def encode_po_string(s):
    if hasattr(sync_translations, 'encode_po_string'):
        return sync_translations.encode_po_string(s)
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') if s else ""

def format_specifiers(s):
    if hasattr(sync_translations, 'format_specifiers'):
        return sync_translations.format_specifiers(s)
    return re.findall(r'%[0-9]*\$?[a-zA-Z]', s) if s else []

def scan_unwrapped_ui_strings():
    unwrapped = []
    for root, _, files in os.walk(SOURCE_DIR):
        if 'languages' in root or 'tools' in root or 'spec' in root: continue
        for file in files:
            if file.endswith('.lua') and file != 'localization_xray.lua':
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    for pat in UI_WIDGET_PATTERNS:
                        for m in re.finditer(pat, content):
                            val = m.group(1)
                            # Ignore icon strings, font files, numbers, single chars, format templates, URLs
                            if (len(val) > 2 and not val.endswith('.svg') and not val.endswith('.png')
                                    and not val.endswith('.ttf') and not val.startswith('%')
                                    and not val.startswith('http://') and not val.startswith('https://')
                                    and not val.startswith('www.')):
                                unwrapped.append((file, val))
    return unwrapped

def extract_keys_from_lua():
    res = sync_translations.extract_keys_from_lua()
    if isinstance(res, tuple):
        return res[0]
    return res

def parse_po(file_path):
    entries = {}
    if not os.path.exists(file_path):
        return entries
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        current_msgid = None
        current_msgstr = None
        in_msgid = False
        in_msgstr = False
        for line in f:
            line_str = line.strip()
            if not line_str or line_str.startswith('#'):
                if current_msgid is not None and current_msgstr is not None:
                    entries[current_msgid] = current_msgstr
                    current_msgid = None
                    current_msgstr = None
                in_msgid = False
                in_msgstr = False
                continue
            if line_str.startswith('msgid '):
                if current_msgid is not None and current_msgstr is not None:
                    entries[current_msgid] = current_msgstr
                m = re.match(r'^msgid "(.*)"$', line_str)
                current_msgid = decode_po_string(m.group(1)) if m else ''
                current_msgstr = None
                in_msgid = True
                in_msgstr = False
            elif line_str.startswith('msgstr '):
                m = re.match(r'^msgstr "(.*)"$', line_str)
                current_msgstr = decode_po_string(m.group(1)) if m else ''
                in_msgid = False
                in_msgstr = True
            elif line_str.startswith('"'):
                m = re.match(r'^"(.*)"$', line_str)
                if m:
                    val = decode_po_string(m.group(1))
                    if in_msgid and current_msgid is not None:
                        current_msgid += val
                    elif in_msgstr and current_msgstr is not None:
                        current_msgstr += val
        if current_msgid is not None and current_msgstr is not None:
            entries[current_msgid] = current_msgstr
    return entries

def save_po(file_path, lang_name, lang_code, entries):
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(f'msgid ""\nmsgstr ""\n"Language-Team: {lang_name}\\n"\n"Language: {lang_code}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for key in sorted(entries.keys()):
            if not key: continue
            val = entries[key]
            escaped_key = encode_po_string(key)
            escaped_val = encode_po_string(val)
            f.write(f'msgid "{escaped_key}"\nmsgstr "{escaped_val}"\n\n')

def run_audit():
    print("==================================================")
    print("       X-RAY TRANSLATION & UI STRING AUDITOR      ")
    print("==================================================\n")

    unwrapped_ui = scan_unwrapped_ui_strings()
    if unwrapped_ui:
        print(f"⚠️ Warning: Found {len(unwrapped_ui)} potentially un-wrapped UI string literals:")
        for fn, s in unwrapped_ui[:10]:
            print(f"   [{fn}] \"{s}\"")
        print()
    else:
        print("✅ 0 Un-wrapped UI String Literals Found!\n")

    used_keys = extract_keys_from_lua()
    print(f"Total Unique Translation Keys Extracted from Lua Source: {len(used_keys)}\n")

    en_path = os.path.join(LANGUAGES_DIR, 'en.po')
    en_entries = parse_po(en_path)
    en_entries.pop("", None)

    # 1. Update en.po if keys are missing
    missing_in_en = used_keys - set(en_entries.keys())
    if missing_in_en:
        print(f"Updating en.po with {len(missing_in_en)} missing master keys...")
        for k in missing_in_en:
            en_entries[k] = k
        save_po(en_path, 'English', 'en', en_entries)

    print(f"✅ English Master (en.po) Key Parity: 100% ({len(en_entries)} keys)!\n")

    # 2. Check and report on target language coverage
    print("--- Target Language Parity & Completeness Audit ---")
    total_issues = 0

    for lang_code, lang_name in sorted(LANG_NAMES.items()):
        if lang_code == 'en': continue
        po_path = os.path.join(LANGUAGES_DIR, f"{lang_code}.po")
        entries = parse_po(po_path)
        entries.pop("", None)

        missing = []
        empty = []
        too_long = []
        spec_mismatch = []

        for key in sorted(en_entries.keys()):
            val = entries.get(key, "")
            en_val = en_entries.get(key, key)
            if key not in entries:
                missing.append(key)
            elif not val or val.strip() == "":
                empty.append(key)
            elif "???" in val:
                empty.append(key)
            elif key in ENCODING_SENSITIVE_KEYS and "?" in val:
                empty.append(key)
            elif format_specifiers(val) != format_specifiers(en_val):
                spec_mismatch.append(key)

            max_length = TRANSLATION_MAX_LENGTHS.get(key)
            if max_length is not None and len(val) > max_length:
                too_long.append((key, val))

        issues_count = len(missing) + len(empty) + len(too_long) + len(spec_mismatch)
        if issues_count > 0:
            total_issues += issues_count
            print(f"❌ {lang_code}.po ({lang_name}): {len(entries)}/{len(en_entries)} keys | {len(missing)} missing | {len(empty)} empty | {len(spec_mismatch)} format mismatches | {len(too_long)} length violations")
        else:
            print(f"✅ {lang_code}.po ({lang_name}): 100% complete ({len(entries)}/{len(en_entries)} keys)")

    print("\n==================================================")
    if total_issues == 0 and len(unwrapped_ui) == 0:
        print("     AUDIT PASSED: 100% MULTILINGUAL PARITY!       ")
    else:
        print(f"     AUDIT FINISHED: {total_issues + len(unwrapped_ui)} ISSUES REPORTED          ")
    print("==================================================")
    return total_issues + len(unwrapped_ui)

if __name__ == "__main__":
    sys.exit(run_audit())
