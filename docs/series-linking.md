# Linking books in a series

X-Ray can carry characters, locations, glossary terms, and timeline recap from earlier volumes into the book you are reading now. Those entries show up with a **[Prior]** label.

This does **not** move or rename your EPUBs. It only copies X-Ray *analysis* between caches. That matters if books arrive one file at a time (Readest sync, email, Calibre “send to device”, a flat `Books/` folder, and so on). You do not need a pre-made series folder on the reader.

## The three files involved

```
Your library (unchanged)
  /sdcard/Books/Le Roi de fer.epub
  /sdcard/Books/02 - La Reine étranglée.epub

Per-book analysis (sidecar, next to each EPUB)
  /sdcard/Books/Le Roi de fer.sdr/xray_cache.lua
  /sdcard/Books/02 - La Reine étranglée.sdr/xray_cache.lua

Shared series index (one file per series name, not per pair of books)
  koreader/settings/xray/series/<slug>.lua
  e.g. rois_maudits.lua
```

| Layer | What it stores | When it is used |
| --- | --- | --- |
| EPUB | The book itself | Never modified by linking |
| Sidecar `*.sdr/xray_cache.lua` | This volume’s X-Ray (and, after a link, copies of prior volumes marked `[Prior]`) | What you see in Characters / Places / Timeline |
| `settings/xray/series/<slug>.lua` | Volume 1, 2, … of that series | Later Fetch / another book in the same series |

On Android, `settings` is typically `/sdcard/koreader/settings/`. On Kindle it is under the KOReader home directory.

## Manual link (reliable path)

Use this when you already analyzed an earlier volume and the current book should inherit it. Typical case: volume 1 finished on the device, volume 2 just synced from Readest, Calibre series names or indexes do not match.

1. Analyze **volume 1** as usual (Fetch X-Ray) until Characters / Places / Timeline look complete.
2. Open **volume 2**.
3. **X-Ray → Series Context → Link prior books…**
4. Confirm the series name (you can edit it; `Les Rois Maudits` and `Rois Maudits` are treated as the same series).
5. Check the earlier volumes. Books in the **same folder** that already have an X-Ray sidecar are listed; same-author titles are pre-checked. Use **Add another book…** if a volume lives in another directory.
6. **Import selected**.

What happens then:

1. X-Ray reads each checked book’s sidecar (`*.sdr/xray_cache.lua`). It does not re-send that book to the AI if the cache is already there.
2. It writes those volumes into `settings/xray/series/<slug>.lua` (creates the file if needed).
3. It merges them into the **current** book’s sidecar as `[Prior]` entries. Opening Characters on volume 2 then shows this volume plus the previous ones (for example 13 local characters + 44 from volume 1, minus name overlap).
4. The EPUBs stay where Readest (or anything else) put them.

**Clear series links** on the current book removes the `[Prior]` copies from *this* sidecar. It does not delete the other book’s analysis, and it does not delete `settings/xray/series/`.

## Automatic Fetch (when metadata is clean)

**X-Ray → Series Context → Fetch / Refresh Series Context** tries to detect the series from EPUB metadata (`series` + `series_index`), then from the KOReader sidecar, then from a filename prefix such as `02 - …`.

That works when every volume has the **same series name** and a real index (1, 2, 3…). It often fails when:

- KOReader exposes the series name but **drops the index** (the plugin used to treat a missing index as “this is book 1”).
- Two files use different labels (`Les Rois Maudits` vs `Rois Maudits`) — those are now normalized to one slug, but an old auto-check may still have marked the book as “don’t ask again”.
- You dismissed the series popup, or the device was offline at first open.

If Fetch says the current book is the first volume and you know it is not, use **Link prior books…** instead. That ignores the bad index and uses the files you pick.

## Readest (and other one-file sync)

Readest (and similar tools) usually drop each EPUB into a library folder, not into a Calibre-style `Series/Book 1/` tree. That is enough:

- Keep volumes of the same series in **one folder** on the reader when you can (for example everything under `Books/`). The linker lists neighbors with an X-Ray cache.
- If a volume landed somewhere else, **Add another book…** and pick its EPUB. It still must have been X-Rayed once (its `.sdr/xray_cache.lua` must exist).
- You never need to regroup files on disk for linking to work. Moving EPUBs after KOReader has opened them can orphan sidecars and reading progress; prefer linking over renaming.

## Requirements

- The prior volume must already have a local X-Ray cache. Linking does not download a recap of a book you never analyzed on this device.
- Series Context can stay enabled; linking works even if the automatic prompt was dismissed for this book.
- Internet is not required for a local sidecar import. Fetch / AI recap still needs a network if you ask it to invent summaries for a volume that has no cache.
