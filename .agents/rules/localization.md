# Localization Rule

Whenever you modify translation keys in the Lua code (e.g., adding or removing `self.loc:t("key")`), you MUST run the synchronization tool to keep the `.po` files consistent.

**Command (Windows/PowerShell):**
```powershell
python tools/sync_translations.py
```

1. `en.po` (Master) is updated with new keys found in the Lua source.
2. All other languages (`de.po`, `es.po`, `fr.po`, `ru.po`, `tr.po`, etc.) are synchronized with the Master.
3. Existing translations are preserved while new keys are added as placeholders.

## AI Prompts Workflow
The AI prompts are stored in `xray.koplugin/prompts/*.lua`. 

Whenever you modify the logic or structure of an AI prompt (e.g., `comprehensive_xray` in `en.lua`):
1.  Apply the changes to the English version first.
2.  **Manually synchronize** the changes to `es.lua`, `pt_br.lua`, and `tr.lua`.
3.  Ensure that all **variable placeholders** (`%s`, `%d`, `%%`) and **JSON keys** remain identical across all languages to avoid parsing errors.
4.  Verify that the "ALGORITHM" and "PROTOCOL" sections are translated accurately to maintain AI steering performance in all regions.
