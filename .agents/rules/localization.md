# Localization Rule

Whenever you modify translation keys in the Lua code (e.g., adding or removing `self.loc:t("key")`), you MUST run the synchronization tool to keep the `.po` files consistent.

**Command:**
```bash
python xray.koplugin/sync_translations.py
```

This ensures that:
1. `en.po` (Master) stays updated with the source code.
2. All other languages (`es.po`, `tr.po`, `pt_br.po`) stay synchronized with the master.
3. Unused keys are automatically pruned.
