-- xray_seriesmanager.lua - STANDALONE series-specific logic for KOReader X-Ray
local ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok or type(lfs) ~= "table" then
    ok, lfs = pcall(require, "lfs")
end
if not ok or type(lfs) ~= "table" then
    lfs = nil
end
local logger = require("logger")
local DataStorage = require("datastorage")

local SeriesManager = {}

function SeriesManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SeriesManager:makeSlug(name)
    if not name then return "" end
    -- Lowercase and replace non-alphanumeric characters with underscores
    local slug = name:lower():gsub("[%s%p]+", "_")
    -- Strip leading/trailing underscores
    slug = slug:gsub("^_+", ""):gsub("_+$", "")
    return slug
end

--- Strip leading Romance articles so "Les Rois Maudits" and "Rois Maudits" share a cache.
function SeriesManager:canonicalSeriesName(name)
    local s = self:foldTitle(name)
    if s == "" then return "" end
    s = s:gsub("^(les|le|la|l|el|los|las|un|une|des|del)%s+", "")
    s = s:gsub("%s+(book|tome|vol|volume)%s+%d+$", "")
    return s
end

function SeriesManager:canonicalSlug(name)
    local folded = self:canonicalSeriesName(name)
    if folded == "" then return self:makeSlug(name) end
    return folded:gsub("%s+", "_")
end

--- Prefer an existing on-disk cache; otherwise use the canonical slug for new series.
function SeriesManager:resolveSlug(name)
    local raw = self:makeSlug(name)
    local canon = self:canonicalSlug(name)
    if raw ~= "" and self:loadSeriesCache(raw) then return raw end
    if canon ~= "" and canon ~= raw and self:loadSeriesCache(canon) then return canon end
    if canon ~= "" then return canon end
    return raw
end

function SeriesManager:parseIndex(value)
    if value == nil or value == "" then return nil end
    if type(value) == "table" then value = value[1] end
    local n = tonumber(value)
    if n and n >= 1 then return math.floor(n) end
    local s = tostring(value)
    n = tonumber(s:match("^%s*(%d+)"))
    if n and n >= 1 then return n end
    return nil
end

--- "02 - La Reine étranglée.epub" → 2
function SeriesManager:indexFromFilename(path_or_name)
    if not path_or_name or path_or_name == "" then return nil end
    local base = path_or_name:match("([^/]+)$") or path_or_name
    local n = tonumber(base:match("^(%d+)%s*%-")) or tonumber(base:match("^(%d+)[%.%)]"))
    if n and n >= 1 then return n end
    return nil
end

--- "02 - Title.sdr" next to a renamed "Title.epub" (Readest) still carries the volume number.
function SeriesManager:indexFromNearbyFilename(book_path)
    if not book_path or not lfs then return nil end
    local dir = book_path:match("^(.*)/[^/]+$")
    local base = book_path:match("([^/]+)$") or ""
    local current_stem = base:gsub("%.[^%.]+$", "")
    if not dir or current_stem == "" then return nil end
    local ok_dir, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok_dir or not iter then return nil end
    for name in iter, dir_obj do
        if type(name) == "string" and name:sub(-4) == ".sdr" then
            local stem = sidecarStem(name)
            if stem ~= current_stem and self:isSameVolume(current_stem, stem) then
                local n = self:indexFromFilename(stem)
                if n then return n end
            end
        end
    end
    return nil
end

--- Fold titles/authors for matching (French accents, punctuation, case).
function SeriesManager:foldTitle(s)
    if type(s) ~= "string" then
        if type(s) == "table" then
            s = table.concat(s, " ")
        else
            s = tostring(s or "")
        end
    end
    -- Keep only the first line (sidecar author sometimes appends narrator).
    s = s:match("^[^\r\n]+") or s
    s = s:lower()
    local accents = {
        ["à"] = "a", ["â"] = "a", ["ä"] = "a",
        ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
        ["î"] = "i", ["ï"] = "i",
        ["ô"] = "o", ["ö"] = "o",
        ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
        ["ç"] = "c", ["œ"] = "oe", ["æ"] = "ae",
    }
    for acc, plain in pairs(accents) do
        s = s:gsub(acc, plain)
    end
    s = s:gsub("[^%w]+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return s
end

--- Same volume under a different filename (Readest re-download, dropped "02 -", "Readaloud", etc.).
function SeriesManager:isSameVolume(a, b)
    if not a or not b or a == "" or b == "" then return false end
    if a == b then return true end
    return self:titlesMatch(a, b)
end

function SeriesManager:titlesMatch(a, b)
    a, b = self:foldTitle(a), self:foldTitle(b)
    if a == "" or b == "" then return false end
    if a == b then return true end
    local shorter, longer
    if #a <= #b then shorter, longer = a, b else shorter, longer = b, a end
    if #shorter < 8 and not shorter:find(" ", 1, true) then
        return false
    end
    return longer:find(shorter, 1, true) and true or false
end

function SeriesManager:authorsMatch(a, b)
    a, b = self:foldTitle(a), self:foldTitle(b)
    if a == "" or b == "" then return false end
    if a == b then return true end
    return a:find(b, 1, true) and true or b:find(a, 1, true) and true or false
end

local function filterCurrentOnly(tbl)
    local res = {}
    for _, item in ipairs(tbl or {}) do
        if item and item.source ~= "series_prior" then
            table.insert(res, item)
        end
    end
    return res
end

function SeriesManager:bookEntryFromSidecar(data, fallback_title)
    if type(data) ~= "table" then return nil end
    return {
        title = data.title or fallback_title,
        author = data.author,
        characters = filterCurrentOnly(data.characters),
        locations = filterCurrentOnly(data.locations),
        terms = filterCurrentOnly(data.terms),
        timeline = filterCurrentOnly(data.timeline),
        from_local_sidecar = true,
    }
end

--- Create-or-update one volume in the shared series cache.
function SeriesManager:upsertBook(slug, index, book_entry, series_name)
    if not slug or not index or not book_entry then return false end
    local cache_data = self:loadSeriesCache(slug) or { books = {} }
    cache_data.books = cache_data.books or {}
    if series_name and series_name ~= "" then
        cache_data.series_name = series_name
    end
    cache_data.books[index] = book_entry
    return self:saveSeriesCache(slug, cache_data)
end

--- Sidecar folder name without ".sdr" (KOReader: `Title.sdr` next to `Title.epub`).
local function sidecarStem(name)
    if not name then return "" end
    return name:gsub("%.sdr$", "")
end

--- Among nearby book sidecars, pick the one that is this prior volume.
function SeriesManager:selectNearbyPrior(want_title, want_author, current_sdr_name, candidates)
    candidates = candidates or {}
    for _, c in ipairs(candidates) do
        if c.name ~= current_sdr_name then
            local folder = sidecarStem(c.name)
            if self:titlesMatch(want_title, c.title) or self:titlesMatch(want_title, folder) then
                return c
            end
        end
    end
    local hits = {}
    for _, c in ipairs(candidates) do
        if c.name ~= current_sdr_name and self:authorsMatch(want_author, c.author) then
            table.insert(hits, c)
        end
    end
    if #hits == 1 then return hits[1] end
    return nil
end

--- List `*.sdr/xray_cache.lua` next to the open book.
function SeriesManager:listNearbySidecars(book_path)
    local out = {}
    if not book_path or not lfs then return out end
    local dir = book_path:match("^(.*)/[^/]+$")
    if not dir then return out end
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok or not iter then return out end
    for name in iter, dir_obj do
        if type(name) == "string" and name:sub(-4) == ".sdr" then
            local cache_file = dir .. "/" .. name .. "/xray_cache.lua"
            local attr = lfs.attributes(cache_file)
            if attr and attr.mode == "file" then
                local loaded, data = pcall(dofile, cache_file)
                if loaded and type(data) == "table" and data.cache_version == "6.0" then
                    table.insert(out, {
                        name = name,
                        title = data.title,
                        author = data.author,
                        data = data,
                    })
                end
            end
        end
    end
    return out
end

function SeriesManager:findLocalPriorBook(book_path, want_title, want_author)
    if not book_path then return nil end
    local base = book_path:match("([^/]+)$") or ""
    local stem = base:gsub("%.[^%.]+$", "")
    local current_sdr = stem .. ".sdr"
    local candidates = self:listNearbySidecars(book_path)
    local picked = self:selectNearbyPrior(want_title, want_author, current_sdr, candidates)
    if not picked then return nil end
    return self:bookEntryFromSidecar(picked.data, sidecarStem(picked.name))
end

local function countList(tbl)
    local n = 0
    for _, item in ipairs(tbl or {}) do
        if item then n = n + 1 end
    end
    return n
end

function SeriesManager:loadBookSidecar(book_path)
    if not book_path then return nil end
    local ok, DocSettings = pcall(require, "docsettings")
    if not ok or not DocSettings or not DocSettings.getSidecarDir then return nil end
    local cache_file = DocSettings:getSidecarDir(book_path) .. "/xray_cache.lua"
    if lfs then
        local attr = lfs.attributes(cache_file)
        if not attr or attr.mode ~= "file" then return nil end
    end
    local loaded, data = pcall(dofile, cache_file)
    if loaded and type(data) == "table" and data.cache_version == "6.0" then
        return data
    end
    return nil
end

function SeriesManager:describeLinkable(epub_path, data, sdr_name)
    data = data or {}
    local stem = sidecarStem(sdr_name) or ""
    if stem == "" and epub_path then
        local base = epub_path:match("([^/]+)$") or epub_path
        stem = base:gsub("%.[^%.]+$", "")
    end
    return {
        epub_path = epub_path,
        name = sdr_name or (stem .. ".sdr"),
        title = data.title or stem,
        author = data.author,
        data = data,
        char_count = countList(data.characters),
        loc_count = countList(data.locations),
        timeline_count = countList(data.timeline),
        file_index = self:indexFromFilename(epub_path or stem),
    }
end

function SeriesManager:readSidecarDocProps(book_path)
    if not book_path then return nil end
    local ok, DocSettings = pcall(require, "docsettings")
    if not ok or not DocSettings or not DocSettings.getSidecarDir then return nil end
    local dir = DocSettings:getSidecarDir(book_path)
    for _, fname in ipairs({ "metadata.epub.lua", "metadata.pdf.lua", "metadata.lua" }) do
        local loaded, data = pcall(dofile, dir .. "/" .. fname)
        if loaded and type(data) == "table" and type(data.doc_props) == "table" then
            return data.doc_props
        end
    end
    return nil
end

--- Nearby books that already have an X-Ray sidecar (for the manual linker).
function SeriesManager:listLinkableBooks(book_path)
    local out = {}
    if not book_path then return out end
    local current_base = book_path:match("([^/]+)$") or ""
    local current_stem = current_base:gsub("%.[^%.]+$", "")
    local dir = book_path:match("^(.*)/[^/]+$")
    for _, c in ipairs(self:listNearbySidecars(book_path)) do
        local stem = sidecarStem(c.name)
        if stem ~= current_stem and not self:isSameVolume(current_stem, stem)
            and not self:isSameVolume(current_stem, c.title) then
            local epub_path
            if dir and lfs then
                for _, ext in ipairs({ ".epub", ".azw3", ".pdf", ".mobi", ".fb2", ".kepub.epub" }) do
                    local candidate = dir .. "/" .. stem .. ext
                    local attr = lfs.attributes(candidate)
                    if attr and attr.mode == "file" then
                        epub_path = candidate
                        break
                    end
                end
            end
            table.insert(out, self:describeLinkable(epub_path, c.data, c.name))
        end
    end
    table.sort(out, function(a, b)
        local ia, ib = a.file_index or 9999, b.file_index or 9999
        if ia ~= ib then return ia < ib end
        return (a.title or "") < (b.title or "")
    end)
    return out
end

-- Detect if book is part of a series
function SeriesManager:detectSeries(props, title, author, ai_helper, book_path)
    props = props or {}
    local series_name = props.series or props.Series
    if type(series_name) == "table" then
        series_name = table.concat(series_name, " ")
    end
    local series_index = props.series_index or props.seriesindex or props.SeriesIndex
    series_index = self:parseIndex(series_index)

    logger.info("XRayPlugin: Series: detectSeries: title=" .. tostring(title) .. ", author=" .. tostring(author))
    logger.info("XRayPlugin: Series: detectSeries: Metadata check - props.series=" .. tostring(series_name) .. ", props.series_index=" .. tostring(series_index))

    if (not series_name or series_name == "") or not series_index then
        local sidecar_props = self:readSidecarDocProps(book_path)
        if sidecar_props then
            if (not series_name or series_name == "") then
                series_name = sidecar_props.series or sidecar_props.Series or series_name
            end
            if not series_index then
                series_index = self:parseIndex(sidecar_props.series_index or sidecar_props.seriesindex)
            end
        end
    end
    if not series_index then
        series_index = self:indexFromFilename(book_path) or self:indexFromNearbyFilename(book_path)
        if series_index then
            logger.info("XRayPlugin: Series: detectSeries: index from filename=" .. tostring(series_index))
        end
    end

    -- 1. Try metadata first (do not invent index=1 when the volume number is missing)
    if series_name and series_name ~= "" then
        logger.info("XRayPlugin: Series: detectSeries: Metadata path taken. Name=" .. tostring(series_name) .. ", index=" .. tostring(series_index))
        return {
            name = series_name,
            index = series_index,
            slug = self:resolveSlug(series_name)
        }
    end
    
    -- 2. Fallback to AI
    if not ai_helper then
        logger.info("XRayPlugin: Series: detectSeries: Metadata fallback to AI skipped because ai_helper is nil")
        return nil
    end
    
    logger.info("XRayPlugin: Series: detectSeries: Metadata fallback to AI starting. Sending detection prompt.")
    local prompt = ai_helper:createPrompt(title, author, nil, "series_detect")
    local result, err_code, err_msg = ai_helper:executeUnifiedRequest(prompt)
    if result and result.is_series then
        local name = result.series_name
        local index = self:parseIndex(result.book_index) or self:indexFromFilename(book_path)
        logger.info("XRayPlugin: Series: detectSeries: AI returned: is_series=" .. tostring(result.is_series) .. ", series_name=" .. tostring(name) .. ", book_index=" .. tostring(index))
        if name and name ~= "" then
            return {
                name = name,
                index = index,
                slug = self:resolveSlug(name)
            }
        end
    else
        logger.info("XRayPlugin: Series: detectSeries: AI call failed or not a series. err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
    end
    
    logger.info("XRayPlugin: Series: detectSeries: Not part of a series.")
    return nil
end

-- Get list of prior books in the series
function SeriesManager:getPriorBookList(series_info, author, ai_helper)
    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        logger.info("XRayPlugin: Series: getPriorBookList: invalid series_info or index <= 1, returning empty list")
        return {}
    end
    
    logger.info("XRayPlugin: Series: getPriorBookList starting for: " .. tostring(series_info.name) .. ", index=" .. tostring(series_info.index))

    if ai_helper then
        logger.info("XRayPlugin: Series: getPriorBookList: Sending AI prior book list prompt.")
        local context = {
            series_name = series_info.name,
            index = series_info.index
        }
        local prompt = ai_helper:createPrompt(nil, author, context, "prior_book_list")
        local result, err_code, err_msg = ai_helper:executeUnifiedRequest(prompt)
        if result and result.prior_books then
            logger.info("XRayPlugin: Series: getPriorBookList: AI returned " .. tostring(#result.prior_books) .. " prior books.")
            return result.prior_books
        else
            logger.info("XRayPlugin: Series: getPriorBookList: AI call failed or returned no list (err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg) .. "). Using local fallback.")
        end
    else
        logger.info("XRayPlugin: Series: getPriorBookList: ai_helper is nil, skipping AI prompt and using local fallback.")
    end
    
    -- Minimal local fallback if AI fails/is missing: generate placeholders
    logger.info("XRayPlugin: Series: getPriorBookList: Generating local fallback list of " .. tostring(series_info.index - 1) .. " placeholder books.")
    local fallback_list = {}
    for i = 1, series_info.index - 1 do
        table.insert(fallback_list, {
            index = i,
            title = string.format("%s (Book %d)", series_info.name, i),
            author = author or "Unknown Author"
        })
    end
    return fallback_list
end

-- Cache path for a series slug
function SeriesManager:getSeriesCachePath(slug)
    if not slug or slug == "" then return nil end
    return DataStorage:getSettingsDir() .. "/xray/series/" .. slug .. ".lua"
end

-- Ensure directory path exists
function SeriesManager:ensureDirectory(path)
    if not lfs then return true end
    local dir = path:match("(.+)/[^/]+$")
    if not dir then return false end
    
    local attr = lfs and lfs.attributes(dir)
    if attr and attr.mode == "directory" then
        return true
    end
    
    -- Use recursive mkdir (os.execute) so parent dirs are created too
    logger.info("SeriesManager: Creating directory:", dir)
    local escaped = dir:gsub("'", "'\\''")
    local rc = os.execute("mkdir -p '" .. escaped .. "'")
    if rc == 0 or rc == true then
        return true
    end

    -- Fallback: try lfs.mkdir (non-recursive, may fail if parent missing)
    if lfs then
        local success, err = lfs.mkdir(dir)
        if success then return true end
        logger.warn("SeriesManager: Failed to create directory:", err or "unknown error")
    end
    return false
end

-- Save series context to global cache
function SeriesManager:saveSeriesCache(slug, data)
    if not slug or not data then
        return false
    end
    
    local cache_file = self:getSeriesCachePath(slug)
    if not cache_file then return false end
    
    if not self:ensureDirectory(cache_file) then
        return false
    end
    
    data.cached_at = os.time()
    data.cache_version = "6.0"
    
    local success, err = pcall(function()
        local f, open_err = io.open(cache_file, "w")
        if not f then
            logger.warn("SeriesManager: Cannot open file for writing:", cache_file)
            return false
        end
        
        f:write("-- X-Ray Series Cache v6.0\n")
        f:write("return ")
        self:serializeToFile(f, data, "")
        f:write("\n")
        f:close()
        logger.info("SeriesManager: Saved series cache to:", cache_file)
        return true
    end)
    
    return success
end

-- Load series context from global cache
function SeriesManager:loadSeriesCache(slug)
    if not slug or slug == "" then return nil end
    local cache_file = self:getSeriesCachePath(slug)
    if not cache_file then return nil end
    
    if lfs then
        local attr = lfs.attributes(cache_file)
        if not attr then return nil end
    else
        local f = io.open(cache_file, "r")
        if f then f:close() else return nil end
    end
    
    local success, data = pcall(dofile, cache_file)
    if success and type(data) == "table" and data.cache_version == "6.0" then
        return data
    end
    return nil
end

-- Stream-serialize to file
function SeriesManager:serializeToFile(f, obj, indent, seen)
    seen = seen or {}
    local t = type(obj)

    if t == "table" then
        if seen[obj] then
            f:write("{--[[circular reference]]}")
            return
        end
        seen[obj] = true

        f:write("{\n")
        local child_indent = indent .. "  "
        for k, v in pairs(obj) do
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
                f:write(child_indent)
                if type(k) == "string" then
                    if k:match("^[%a_][%w_]*$") then
                        f:write(k)
                        f:write(" = ")
                    else
                        f:write("[")
                        f:write(string.format("%q", k))
                        f:write("] = ")
                    end
                else
                    f:write("[")
                    f:write(tostring(k))
                    f:write("] = ")
                end
                self:serializeToFile(f, v, child_indent, seen)
                f:write(",\n")
            end
        end
        f:write(indent)
        f:write("}")

    elseif t == "string" then
        f:write(string.format("%q", obj))
    elseif t == "number" or t == "boolean" then
        f:write(tostring(obj))
    else
        f:write("nil")
    end
end

return SeriesManager
