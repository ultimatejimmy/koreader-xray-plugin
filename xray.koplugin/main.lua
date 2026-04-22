-- X-Ray Plugin for KOReader v2.0.0

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Trapper = require("ui/trapper")
local logger = require("logger")
local XRayLogger = require("xray_logger")
local _ = require("gettext")
local Screen = require("device").screen

local XRayPlugin = WidgetContainer:extend{
    name = "xray",
    is_doc_only = true,
}

function XRayPlugin:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    -- Clean up legacy un-prefixed module files from older versions to prevent namespace collisions
    local legacy_files = { "aihelper.lua", "cachemanager.lua", "chapteranalyzer.lua", "lookupmanager.lua", "updater.lua" }
    for _, file in ipairs(legacy_files) do
        local old_path = self.path .. "/" .. file
        local f = io.open(old_path, "r")
        if f then
            f:close()
            os.remove(old_path)
            self:log("XRayPlugin: Cleaned up legacy file " .. file)
        end
    end

    local Localization = require("localization_xray")
    self.loc = Localization
    self.loc:init(self.path)

    XRayLogger:init(self.path)
    
    local AIHelper = require("xray_aihelper")
    self.ai_helper = AIHelper
    self.ai_helper:init(self.path)
    self.ai_provider = self.ai_helper.default_provider or "gemini"
    
    self.xray_mode_enabled = true
    if self.ai_helper.settings and self.ai_helper.settings.xray_mode_enabled ~= nil then
        self.xray_mode_enabled = self.ai_helper.settings.xray_mode_enabled
    end

    -- Auto-fetch on chapter change (session state)
    self.last_auto_chapter = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false
    self.auto_fetch_enabled = not (self.ai_helper.settings and
        self.ai_helper.settings.auto_fetch_on_chapter == false)

    -- Modular lookup logic for text selection
    local LookupManager = require("xray_lookupmanager")
    self.lookup_manager = LookupManager:new(self)
    
    self:log("XRayPlugin: Initialized with language: " .. self.loc:getLanguage())
    self:onDispatcherRegisterActions()
    
    if self.ui then
        self.ui:registerKeyEvents({
            ShowXRayMenu = {
                { "Alt", "X" },
                event = "ShowXRayMenu",
            },
        })

        -- Hook into Highlight Dialog (long-press on existing highlights)
        if self.ui.highlight then
            self.ui.highlight:addToHighlightDialog("xray_lookup", function(_reader_highlight_instance)
                if not self.xray_mode_enabled then return end
                return {
                    text = "X-Ray",
                    callback = function()
                        self.lookup_manager:handleLookup(_reader_highlight_instance.selected_text.text)
                    end,
                }
            end)
        end
    end
    
    logger.info("XRayPlugin: Initialized with language:", self.loc:getLanguage())
end

-- Hook for Dictionary/Selection Popup (single word)
function XRayPlugin:onDictButtonsReady(dict_popup, dict_buttons)
    if not self.xray_mode_enabled then return end
    
    local xray_button = {
        text = "X-Ray",
        callback = function()
            self.lookup_manager:handleLookup(dict_popup.word)
        end,
    }

    -- KOReader expects rows of buttons. Wrap our button in a row.
    -- We insert it at index 2 (usually the second row) to ensure it's visible.
    if #dict_buttons >= 1 then
        table.insert(dict_buttons, 2, { xray_button })
    else
        table.insert(dict_buttons, { xray_button })
    end
end

function XRayPlugin:log(msg)
    XRayLogger:log(msg)
end

function XRayPlugin:onReaderReady()
    self:autoLoadCache()
    -- Reset per-session chapter fetch tracking
    self.last_auto_chapter = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false

    -- Weekly silent update check
    UIManager:scheduleIn(10, function()
        self:checkWeeklyUpdate()
    end)
end

function XRayPlugin:onPageUpdate(pageno)
    self:log("XRayPlugin: onPageUpdate for pageno " .. tostring(pageno))
    self.last_pageno = pageno
    if not self.auto_fetch_enabled then return end
    
    self:log("XRayPlugin: onPageUpdate for pageno " .. tostring(pageno))
    if not self.ui or not self.ui.document then return end

    -- Resolve current chapter title from TOC
    local toc = self.ui.document:getToc()
    if not toc or #toc == 0 then
        self:log("XRayPlugin: No TOC found for page " .. tostring(pageno))
        return
    end

    local chapter_title = nil
    local chapter_page = nil
    for _, entry in ipairs(toc) do
        if entry.page and entry.page <= pageno then
            chapter_title = entry.title
            chapter_page = entry.page
        else
            break
        end
    end

    if not chapter_title then
        self:log("XRayPlugin: No chapter found for page " .. tostring(pageno))
        return
    end

    local unique_id = chapter_title .. "_" .. tostring(chapter_page)

    -- Skip non-narrative chapters (Frontmatter/Backmatter)
    if self:isNonNarrativeChapter(chapter_title) then 
        if not self.chapters_fetched[unique_id] then
            self:log("XRayPlugin: Skipping non-narrative chapter: " .. tostring(chapter_title) .. " (page " .. tostring(chapter_page) .. ")")
            self.chapters_fetched[unique_id] = true
        end
        return 
    end

    -- Check if it's already populated in the timeline data
    local is_populated = false
    local norm_title = self:normalizeChapterName(chapter_title)
    for _, ev in ipairs(self.timeline or {}) do
        -- Duplicate = same chapter name AND same page number.
        -- If either page is nil, treat as distinct (prevents omnibus chapter collapse).
        if self:normalizeChapterName(ev.chapter or "") == norm_title then
            if ev.page and chapter_page and ev.page == chapter_page then
                is_populated = true
                break
            end
        end
    end

    if is_populated then
        if not self.chapters_fetched[unique_id] then
            self:log("XRayPlugin: Chapter already populated in data: " .. tostring(chapter_title) .. " (page " .. tostring(chapter_page) .. ")")
        end
        self.chapters_fetched[unique_id] = true
        return
    end

    -- It is NOT populated. Limit retries to prevent API spamming.
    self.fetch_attempts = self.fetch_attempts or {}
    if (self.fetch_attempts[unique_id] or 0) >= 3 then
        self:log("XRayPlugin: Max fetch attempts reached for: " .. tostring(unique_id))
        self.chapters_fetched[unique_id] = true
        return
    end
    self.last_pageno = pageno
    self:log("XRayPlugin: onPageUpdate for " .. unique_id)

    if not self.auto_fetch_enabled then return end

    -- Already fetched this chapter this session?
    if self.chapters_fetched[unique_id] then 
        self:log("XRayPlugin: Already fetched chapter this session: " .. tostring(unique_id))
        return 
    end

    -- Same chapter as before (no change)?
    if unique_id == self.last_auto_chapter then return end
    self.last_auto_chapter = unique_id

    -- Debounce: ignore if a fetch is already scheduled
    if self.bg_fetch_pending or self.bg_fetch_active then 
        self:log("XRayPlugin: Fetch already pending/active. Skipping trigger for " .. tostring(chapter_title))
        return 
    end
    self.bg_fetch_pending = true

    -- Wait 2s for the reader to settle on the new chapter before fetching
    UIManager:scheduleIn(2, function()
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end)
end

function XRayPlugin:triggerBackgroundMergeFetch(chapter_title)
    self:log("XRayPlugin: triggerBackgroundMergeFetch called for: " .. tostring(chapter_title))
    if self.bg_fetch_active then return end
    if not self.ui or not self.ui.document then return end

    -- SILENT NETWORK CHECK: use isOnline() instead of runWhenOnline to avoid "white box" connecting dialogs
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isOnline() then
        -- Safety Check: Ensure API keys are configured before background activity
        if not self.ai_helper:hasApiKey() then
            self:log("XRayPlugin: Skipping auto-fetch (No API keys configured)")
            return
        end

        -- Cooldown check to prevent API spamming
        local cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        local now = os.time()
        if self.last_bg_fetch_time and (now - self.last_bg_fetch_time) < cooldown then
            self:log("XRayPlugin: Skipping auto-fetch (cooldown active: " .. (cooldown - (now - self.last_bg_fetch_time)) .. "s left)")
            return
        end
        self.last_bg_fetch_time = now

        local current_page = self.ui:getCurrentPage()
        local total_pages = self.ui.document:getPageCount()
        if not total_pages or total_pages == 0 then return end
        local reading_percent = math.floor((current_page / total_pages) * 100)
        
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
        
        local is_update = true
        if not self.timeline or #self.timeline == 0 then
            is_update = false
            self:log("XRayPlugin: Cache is empty. Switching to normal fetch instead of merge.")
        else
            self:log("XRayPlugin: Auto-merge fetch for chapter: " .. tostring(chapter_title))
        end
        
        self.fetch_attempts = self.fetch_attempts or {}
        self.fetch_attempts[chapter_title] = (self.fetch_attempts[chapter_title] or 0) + 1
        self:continueWithFetch(reading_percent, is_update, last_fetch_page, true) -- is_silent=true
    else
        -- Silently skip if offline
        self:log("XRayPlugin: Skipping auto-merge (offline)")
    end
end

function XRayPlugin:onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("xray_quick_menu", {
        category = "none",
        event = "ShowXRayQuickMenu",
        title = self.loc:t("quick_menu_title") or "X-Ray Quick Menu",
        general = true,
        separator = true,
    })
    Dispatcher:registerAction("xray_characters", {
        category = "none",
        event = "ShowXRayCharacters",
        title = self.loc:t("menu_characters") or "Characters",
        general = true,
    })
end

function XRayPlugin:onShowXRayQuickMenu()
    self:showQuickXRayMenu()
    return true
end

function XRayPlugin:onShowXRayMenu()
    self:showQuickXRayMenu()
    return true
end

function XRayPlugin:autoLoadCache()
    if not self.cache_manager then
        local CacheManager = require("xray_cachemanager")
        self.cache_manager = CacheManager:new()
    end
    
    local book_path = self.ui.document.file
    logger.info("XRayPlugin: Auto-loading cache for:", book_path)
    self:log("XRayPlugin: Auto-loading cache for: " .. tostring(book_path))
    local cached_data = self.cache_manager:loadCache(book_path)
    
    if cached_data then
        self:log("XRayPlugin: Cache loaded successfully")
        -- Set raw data immediately so the reader can render first.
        -- Pages were already assigned at fetch time and stored in the cache,
        -- so the data is usable as-is; we just need to sort/dedup.
        self.book_data = cached_data
        self.characters = cached_data.characters or {}
        self.locations = cached_data.locations or {}
        self.timeline = cached_data.timeline or {}
        self.historical_figures = cached_data.historical_figures or {}
        if cached_data.author_info then
            self.author_info = cached_data.author_info
        else
            self.author_info = {
                name = cached_data.author,
                description = cached_data.author_bio,
                birthDate = cached_data.author_birth,
                deathDate = cached_data.author_death
            }
        end
        if #self.characters > 0 then self.xray_mode_enabled = true end

        -- Defer the expensive sort/dedup/page-assignment to the next scheduler
        -- tick so the reader can render the book page before we process.
        -- NOTE: allow_findtext is intentionally false here — pages are already
        -- stored in the cache; document:findText() must never block the main
        -- thread at open time (it freezes the Kindle for many seconds on
        -- omnibus books).
        UIManager:scheduleIn(0, function()
            if not self.ui or not self.ui.document then return end
            self:log("XRayPlugin: Running deferred post-load processing")
            -- Fast restore of sort order using the persisted sort_order field.
            local function restoreOrder(list)
                table.sort(list, function(a, b)
                    return (a.sort_order or 9999) < (b.sort_order or 9999)
                end)
            end
            restoreOrder(self.characters)
            restoreOrder(self.historical_figures)
            -- Repair missing page numbers from old caches (Strategies 1-5 only,
            -- no document text search).
            local toc = self.ui.document:getToc()
            self:assignTimelinePages(self.timeline, toc, false)
            self:sortTimelineByTOC(self.timeline)
            -- Repair any duplicates that may have accumulated in previous sessions
            self.characters = self:deduplicateByName(self.characters, "name")
            self.historical_figures = self:deduplicateByName(self.historical_figures, "name")
            self.locations = self:deduplicateByName(self.locations, "name")
            self:log("XRayPlugin: Deferred post-load processing complete")
        end)
    else
        self:log("XRayPlugin: No cache found or failed to load")
    end
end

function XRayPlugin:getMenuCounts()
    return {
        characters = self.characters and #self.characters or 0,
        locations = self.locations and #self.locations or 0,
        timeline = self.timeline and #self.timeline or 0,
        historical_figures = self.historical_figures and #self.historical_figures or 0,
    }
end

local reader_menu_order = require("ui/elements/reader_menu_order")
if reader_menu_order and reader_menu_order.tools then
    local found = false
    for _, v in ipairs(reader_menu_order.tools) do
        if v == "xray" then found = true; break end
    end
    if not found then table.insert(reader_menu_order.tools, 1, "xray") end
end

function XRayPlugin:getSubMenuItems()
    self.current_xray_menu_table = {
        {
            text = self.loc:t("menu_characters") or "Characters",
            keep_menu_open = true,
            callback = function() self:showCharacters() end,
        },
        {
            text = self.loc:t("menu_timeline") or "Timeline",
            keep_menu_open = true,
            callback = function() self:showTimeline() end,
        },
        {
            text = self.loc:t("menu_historical_figures") or "Historical Figures",
            keep_menu_open = true,
            callback = function() self:showHistoricalFigures() end,
        },
        {
            text = self.loc:t("menu_locations") or "Locations",
            keep_menu_open = true,
            callback = function() self:showLocations() end,
        },
        {
            text = self.loc:t("menu_author_info"),
            keep_menu_open = true,
            callback = function() self:showAuthorInfo() end,
            separator = true,
        },
        {
            text = self.loc:t("menu_fetch_xray") or "Fetch X-Ray Data",
            keep_menu_open = true,
            callback = function() self:fetchFromAI() end,
        },
        {
            text = self.loc:t("menu_update_xray") or "Update X-Ray Data (Merge)",
            keep_menu_open = true,
            callback = function() self:updateFromAI() end,
            separator = true,
        },
        {
            text = "Settings",
            keep_menu_open = true,
            sub_item_table = {
                {
                    text = "Spoiler Settings",
                    keep_menu_open = true,
                    callback = function() self:showSpoilerSettings() end,
                },
                {
                    text = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
                    keep_menu_open = true,
                    callback = function() self:showAutoUpdateSettings() end,
                },
                {
                    text = self.loc:t("menu_xray_mode"),
                    keep_menu_open = true,
                    callback = function() self:toggleXRayMode() end,
                },
                {
                    text = self.loc:t("menu_language") or "Language",
                    keep_menu_open = true,
                    callback = function() self:showLanguageSelection() end,
                },
                {
                    text = self.loc:t("menu_ai_settings"),
                    keep_menu_open = true,
                    sub_item_table = {
                        {
                            text = "Primary AI Model",
                            keep_menu_open = true,
                            sub_item_table_func = function() return self:getAIModelSelectionMenu("primary") end
                        },
                        {
                            text = "Secondary AI Model",
                            keep_menu_open = true,
                            sub_item_table_func = function() return self:getAIModelSelectionMenu("secondary") end,
                            separator = true,
                        },
                        {
                            text = self.loc:t("menu_gemini_key"), 
                            keep_menu_open = true,
                            sub_item_table_func = function() return self:getAPIKeySelectionMenu("gemini", "Google Gemini") end,
                            separator = true,
                        },
                        {
                            text = self.loc:t("menu_chatgpt_key"), 
                            keep_menu_open = true,
                            sub_item_table_func = function() return self:getAPIKeySelectionMenu("chatgpt", "ChatGPT") end,
                            separator = true,
                        },
                        {
                            text = "View All Config Values", 
                            keep_menu_open = true,
                            callback = function() self:showConfigSummary() end,
                        },
                    }
                }
            }
        },
        {
            text = "Maintenance",
            keep_menu_open = true,
            sub_item_table = {
                {
                    text = self.loc:t("menu_clear_cache"),
                    keep_menu_open = true,
                    callback = function() self:clearCache() end,
                },
                {
                    text = self.loc:t("menu_clear_logs") or "Clear Logs",
                    keep_menu_open = true,
                    callback = function() self:clearLogs() end,
                },
                {
                    text = self.loc:t("updater_check") or "Check for Updates",
                    keep_menu_open = true,
                    callback = function()
                        local updater = require("xray_updater")
                        updater.checkForUpdates(self.loc)
                    end,
                },
            }
        },
        {
            text = self.loc:t("menu_about"),
            keep_menu_open = true,
            callback = function() self:showAbout() end,
        },
    }
    
    return self.current_xray_menu_table
end



function XRayPlugin:addToMainMenu(menu_items)
    menu_items.xray = {
        text = self.loc:t("menu_xray") or "X-Ray",
        sorting_hint = "tools",
        callback = function() self:showQuickXRayMenu() end,
        hold_callback = function() self:showFullXRayMenu() end,
        sub_item_table_func = function() return self:getSubMenuItems() end,
    }
end

function XRayPlugin:sortDataByFrequency(list, text, key)
    if not list or #list == 0 then return list end

    -- Role importance weights (higher = more important)
    local role_weights = {
        protagonist = 100,
        main = 90,
        ["main character"] = 90,
        deuteragonist = 80,
        major = 70,
        antagonist = 70,
        villain = 70,
        ["primary antagonist"] = 70,
        supporting = 40,
        secondary = 30,
        minor = 10,
        background = 5,
    }

    local lower_text = text and string.lower(text) or ""

    for _, item in ipairs(list) do
        local name = item[key or "name"]
        if name then
            local lower_name = string.lower(name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")

            -- Signal 1: Role weight
            local role_score = 0
            local role = string.lower(item.role or "")
            for role_key, weight in pairs(role_weights) do
                if role:find(role_key, 1, true) then
                    if weight > role_score then role_score = weight end
                end
            end

            -- Signal 2: Frequency in text (normalized by name length to prevent
            -- short first-name references inflating minor character scores)
            local freq = 0
            if lower_text ~= "" then
                local _, count = string.gsub(lower_text, lower_name, "")
                -- Also try matching just the first name (more natural prose refs)
                local first_name = name:match("^(%S+)")
                if first_name and #first_name > 3 then
                    local lower_first = string.lower(first_name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
                    local _, first_count = string.gsub(lower_text, lower_first, "")
                    -- Use max(full_name, first_name/2) to avoid over-weighting common first names
                    count = math.max(count, math.floor(first_count / 2))
                end
                -- Normalize: divide by name length bucket to reduce short-name bias
                local name_len_factor = math.max(1, math.floor(#name / 4))
                freq = math.floor(count / name_len_factor)
            end

            item._sort_score = role_score * 1000 + freq
        else
            item._sort_score = 0
        end
    end

    table.sort(list, function(a, b)
        return (a._sort_score or 0) > (b._sort_score or 0)
    end)
    -- Stamp a persistent sort_order so cache loads can use a cheap numeric sort
    -- instead of rerunning the full regex-based scoring.
    for i, item in ipairs(list) do
        item.sort_order = i
    end
    return list
end

-- Remove duplicate entries by name (case-insensitive exact match).
-- Keeps the first occurrence so that sort_order is preserved.
function XRayPlugin:deduplicateByName(list, key)
    key = key or "name"
    if not list or #list == 0 then return list end
    local seen = {}
    local deduped = {}
    for _, item in ipairs(list) do
        local k = (item[key] or ""):lower()
        if k ~= "" and not seen[k] then
            seen[k] = true
            table.insert(deduped, item)
        elseif k == "" then
            table.insert(deduped, item) -- keep unnamed entries as-is
        end
    end
    return deduped
end


function XRayPlugin:showLanguageSelection()
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    
    local current_lang = "en"
    if self.loc and self.loc.getLanguage then
        current_lang = self.loc:getLanguage()
    end
    
    local function changeLang(lang_code)
        UIManager:close(self.ldlg)
        if self.loc and self.loc.setLanguage then
            self.loc:setLanguage(lang_code)
            if self.ai_helper then
                self.ai_helper:saveSettings({ language = lang_code })
            end
        end
        
        local msg = (self.loc and self.loc:t("language_changed")) or "Language changed"
        local restart_msg = (self.loc and self.loc:t("please_restart")) or "Please close and reopen the book."
        
        UIManager:show(InfoMessage:new{
            text = "[OK] " .. msg .. "\n\n" .. restart_msg,
            timeout = 4 
        })
    end
    
    local buttons = {
        {{ text = "English" .. (current_lang == "en" and " [OK]" or ""), callback = function() changeLang("en") end }},
        {{ text = "Türkçe" .. (current_lang == "tr" and " [OK]" or ""), callback = function() changeLang("tr") end }},
        {{ text = "Português" .. (current_lang == "pt_br" and " [OK]" or ""), callback = function() changeLang("pt_br") end }},
        {{ text = "Español" .. (current_lang == "es" and " [OK]" or ""), callback = function() changeLang("es") end }},
    }
    
    local dialog_title = (self.loc and self.loc:t("menu_language")) or "Language Selection"
    self.ldlg = ButtonDialog:new{title = dialog_title, buttons = buttons}
    UIManager:show(self.ldlg)
end

function XRayPlugin:showCharacters()
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 })
        return
    end

    local items = {
        { text = "⌕ " .. self.loc:t("search_character"), callback = function() self:showCharacterSearch() end },
        { text = "✚ " .. (self.loc:t("menu_fetch_more_chars") or "Fetch More Characters"), callback = function() self:fetchMoreCharacters() end, separator = true },
    }
    for _, char in ipairs(self.characters) do
        local name = char.name or "Unknown"
        local text = "• " .. name
        if char.description and #char.description > 0 then text = text .. "\n  " .. char.description:sub(1, 80) .. (#char.description > 80 and "..." or "") end
        table.insert(items, { text = text, callback = function() self:showCharacterDetails(char) end })
    end

    -- Close any existing character menu before showing the updated one
    if self.char_menu then
        UIManager:close(self.char_menu)
        self.char_menu = nil
    end

    self.char_menu = Menu:new{
        title = self.loc:t("menu_characters") .. " (" .. #self.characters .. ")",
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        close_callback = function() self.char_menu = nil end,
    }
    UIManager:show(self.char_menu)
end

function XRayPlugin:showCharacterDetails(character)
    local lines = { "NAME: " .. (character.name or "???"), "ROLE: " .. (character.role or "---"), "GENDER: " .. (character.gender or "---"), "OCCUPATION: " .. (character.occupation or "---"), "", "DESCRIPTION:", character.description or "---" }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
end

function XRayPlugin:fetchFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100)
        else
            self:continueWithFetch(reading_percent)
        end
    end)
end

function XRayPlugin:updateFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        local last_fetch_page = nil
        if self.book_data and self.book_data.last_fetch_page then
            last_fetch_page = self.book_data.last_fetch_page
        end
        self:log("XRayPlugin: updateFromAI - last_fetch_page=" .. tostring(last_fetch_page))
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100, true)
        else
            self:continueWithFetch(reading_percent, true, last_fetch_page)
        end
    end)
end

function XRayPlugin:showAutoUpdateSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local is_enabled = self.auto_fetch_enabled
        local current_cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
            text = "Background fetching frequency:",
            buttons = {
                {
                    {
                        text = (not is_enabled and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_disabled") or "Disabled"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = false
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = false })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 0 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_aggressive") or "Aggressive: checks every new chapter"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 0 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 300 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_balanced") or "Balanced: checks at most every 5 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 300 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 900 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_economical") or "Economical: checks at most every 15 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 900 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 1800 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_sparse") or "Sparse: checks at most every 30 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 1800 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("auto_update_freq_about") or "Auto-update checks for new chapter data in the background as you read.\n\nLIMITS & PERFORMANCE\nFrequent background requests can drain BATTERY LIFE and may hit AI PROVIDER RATE LIMITS.\n\nMODES\n• Disabled: No background requests\n• Aggressive: Checks every time you enter a new chapter\n• Balanced: Checks at most every 5 minutes (recommended)\n• Economical: Checks at most every 15 minutes\n• Sparse: Checks at most every 30 minutes\n\nNote: skipped chapters will be included in the next update.",
                                timeout = 120
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function XRayPlugin:showSpoilerSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local current_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
            text = "Select your spoiler preference for X-Ray data:",
            buttons = {
                {
                    {
                        text = (current_setting == "spoiler_free" and "[✓] " or "[  ] ") .. (self.loc:t("spoiler_free_menu_option") or "Spoiler-free"),
                        callback = function()
                            self.ai_helper:saveSettings({ spoiler_setting = "spoiler_free" })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = (current_setting == "full_book" and "[✓] " or "[  ] ") .. (self.loc:t("full_book_option") or "Full Book Mode"),
                        callback = function()
                            self.ai_helper:saveSettings({ spoiler_setting = "full_book" })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("spoiler_free_about") or "Spoiler-free mode limits AI extraction to the pages you have already read (up to your current page), preventing spoilers from future chapters.\n\nFull Book Mode analyzes the entire book, which may contain spoilers.",
                                timeout = 30
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

-- Normalize chapter names for fuzzy comparison (e.g. "CHAPTER THIRTEEN" matches "Chapter 13")
local word_to_num = {
    one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10,
    eleven=11,twelve=12,thirteen=13,fourteen=14,fifteen=15,sixteen=16,
    seventeen=17,eighteen=18,nineteen=19,twenty=20,
    ["twenty-one"]=21,["twenty-two"]=22,["twenty-three"]=23,["twenty-four"]=24,["twenty-five"]=25,
    ["twenty-six"]=26,["twenty-seven"]=27,["twenty-eight"]=28,["twenty-nine"]=29,thirty=30,
    ["thirty-one"]=31,["thirty-two"]=32,["thirty-three"]=33,["thirty-four"]=34,["thirty-five"]=35,
    ["thirty-six"]=36,["thirty-seven"]=37,["thirty-eight"]=38,["thirty-nine"]=39,forty=40,
    ["forty-one"]=41,["forty-two"]=42,["forty-three"]=43,["forty-four"]=44,["forty-five"]=45,
    ["forty-six"]=46,["forty-seven"]=47,["forty-eight"]=48,["forty-nine"]=49,fifty=50,
}
local roman_map = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }
local function romanToDecimal(s)
    local res = 0
    local prev = 0
    for i = #s, 1, -1 do
        local curr = roman_map[s:sub(i, i)]
        if not curr then return nil end
        if curr < prev then
            res = res - curr
        else
            res = res + curr
        end
        prev = curr
    end
    return res
end

function XRayPlugin:normalizeChapterName(name)
    if not name then return "" end
    local s = name:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Replace written-out numbers with digits using word boundaries
    for word, num in pairs(word_to_num) do
        s = s:gsub("%f[%a]" .. word .. "%f[%A]", tostring(num))
    end
    -- Strip common prefixes like "chapter" so "chapter 13" and "13" both become "13"
    s = s:gsub("^chapter%s*", ""):gsub("^ch%.?%s*", "")
    s = s:gsub("^part%s*", ""):gsub("^book%s*", "")
    
    -- Try to convert Roman numerals if the remaining string is a valid Roman numeral
    -- We only do this if it's not already a digit
    if not s:match("^%d+$") and s:match("^[ivxlcdm]+$") then
        local dec = romanToDecimal(s)
        if dec then s = tostring(dec) end
    end
    
    return s
end

-- Check if a chapter name is non-narrative (frontmatter/backmatter)
function XRayPlugin:isNonNarrativeChapter(title)
    if not title then return true end
    local lower = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if lower == "" then return true end
    local patterns = {
        "^cover$", "^title", "^half%-title", "^copyright", "^table of contents",
        "^contents$", "^dedication", "^acknowledgment", "^also by", "^other books",
        "^about the author", "^about the", "^epigraph$", "^foreword$",
        "^preface$", "^appendix", "^glossary", "^index$", "^notes$",
        "^bibliography", "^colophon", "^frontispiece", "^books by",
        "^praise for", "^reviews", "^blurb",
    }
    for _, pat in ipairs(patterns) do
        if lower:match(pat) then return true end
    end
    return false
end

-- Assign TOC page numbers to timeline events.
-- For omnibus books, the same chapter name/number can appear multiple times at different pages.
-- We use ordered queues per key so the Nth AI "Chapter 1" maps to the Nth TOC "Chapter 1".
--
-- allow_findtext: when true, Strategy 6 (document:findText) is used as a last resort
--   for events that could not be matched via TOC. This is a blocking operation and must
--   NEVER be called at cache-load time (causes a multi-second freeze on old Kindles).
--   Pass true only when processing freshly-fetched AI data (finalizeXRayData).
function XRayPlugin:assignTimelinePages(timeline, toc, allow_findtext)
    if not toc or not timeline or #timeline == 0 then return end

    -- Build ORDERED QUEUES (not single-value maps) for each match strategy.
    -- key → list of pages in TOC order, so the Nth event with that key gets the Nth page.
    local q_norm   = {}  -- normalized title → {page, page, ...}
    local q_number = {}  -- leading digit    → {page, page, ...}
    local q_suffix = {}  -- title-after-num  → {page, page, ...}
    local all_toc  = {}  -- flat list {norm, page, used} for substring fallback

    local function push(t, key, val)
        if not t[key] then t[key] = { list = {}, idx = 0 } end
        table.insert(t[key].list, val)
    end

    for _, entry in ipairs(toc) do
        if entry.page and entry.title then
            local p = tonumber(entry.page)
            if p then
                local norm = self:normalizeChapterName(entry.title)
                push(q_norm, norm, p)

                local num = norm:match("^(%d+)")
                if num then push(q_number, num, p) end

                local suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
                if suffix and suffix ~= "" then push(q_suffix, suffix, p) end

                table.insert(all_toc, { norm = norm, page = p, used = false })
            end
        end
    end

    -- Pop the next unused page for a key (consumes in order)
    local function pop(q, key)
        local bucket = q[key]
        if not bucket then return nil end
        bucket.idx = bucket.idx + 1
        return bucket.list[bucket.idx]
    end

    for _, ev in ipairs(timeline) do
        local norm = self:normalizeChapterName(ev.chapter or "")
        local page = nil

        -- Strategy 1: Exact normalized title (queue-based)
        if q_norm[norm] then
            page = pop(q_norm, norm)
        end

        -- Strategy 2: Leading number (queue-based)
        if not page then
            local num = norm:match("^(%d+)")
            if num and q_number[num] then
                page = pop(q_number, num)
            end
        end

        -- Strategy 3: AI suffix vs TOC suffix or norm (queue-based)
        if not page then
            local ai_suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
            if ai_suffix then
                if q_suffix[ai_suffix] then
                    page = pop(q_suffix, ai_suffix)
                elseif q_norm[ai_suffix] then
                    page = pop(q_norm, ai_suffix)
                end
            end
        end

        -- Strategy 4: AI title as suffix (queue-based)
        if not page and q_suffix[norm] then
            page = pop(q_suffix, norm)
        end

        -- Strategy 5: Substring match (linear scan, consume each TOC entry once)
        if not page and #norm > 2 then
            for _, t in ipairs(all_toc) do
                if not t.used then
                    if t.norm:find(norm, 1, true) or norm:find(t.norm, 1, true) then
                        page = t.page
                        t.used = true
                        break
                    end
                end
            end
        end

        -- Strategy 6: NO-TOC FALLBACK - search document text for the chapter heading.
        -- Gated behind allow_findtext because document:findText() is a blocking call that
        -- can freeze the UI for many seconds on large books / old hardware.
        if allow_findtext and not page and self.ui and self.ui.document and self.ui.document.findText then
            if #norm > 3 and not norm:match("^section") then
                local success, results = pcall(function()
                    return self.ui.document:findText(ev.chapter or "", 20)
                end)
                if success and results and #results > 0 then
                    page = results[1].page
                end
            end
        end

        if page then
            ev.page = tonumber(page)
        end
    end
end

-- Sort a timeline table chronologically by the page number stored on each event.
-- Pages are assigned from the TOC at fetch time and persisted in the cache,
-- so no TOC re-lookup is needed here. Events without a page sort to the end.
function XRayPlugin:sortTimelineByTOC(timeline)
    if not timeline or #timeline == 0 then return end
    
    -- Store original index for a stable sort (prevents shuffling events on the same page)
    for i, ev in ipairs(timeline) do ev._sort_idx = i end
    
    table.sort(timeline, function(a, b)
        -- Primary key: Page number (must be numeric)
        local ap = tonumber(a.page) or 999999
        local bp = tonumber(b.page) or 999999
        
        if ap ~= bp then
            return ap < bp
        end
        
        -- Secondary key: Original AI response order (stability)
        -- NOTHING about the chapter title is used for sorting here.
        return (a._sort_idx or 0) < (b._sort_idx or 0)
    end)
    
    -- Clean up temporary index
    for _, ev in ipairs(timeline) do ev._sort_idx = nil end
end

local function sanitizeMetadata(val)
    if type(val) == "string" then return val
    elseif type(val) == "table" then return table.concat(val, ", ")
    else return "Unknown" end
end

function XRayPlugin:continueWithFetch(reading_percent, is_update, last_fetch_page, is_silent)
    if is_silent then
        self.bg_fetch_active = true
    end
    if not self.ai_helper then
        local AIHelper = require("xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)
    local wait_msg
    local is_cancelled = false
    
    if not is_silent then
        local fetch_text = is_update and self.loc:t("updating_ai", self.ai_provider or "AI") or self.loc:t("fetching_ai", self.ai_provider or "AI")
        wait_msg = InfoMessage:new{ text = fetch_text .. "\n\n" .. title .. "\n\n" .. self.loc:t("fetching_wait"), timeout = 120 }
        UIManager:show(wait_msg)
    end
    
    UIManager:scheduleIn(0.5, function()
        if is_cancelled then return end
        if not self.chapter_analyzer then self.chapter_analyzer = require("xray_chapteranalyzer"):new() end

        -- 1a. Lightweight prep: resolve current page and find first missing page
        local current_page = self.ui:getCurrentPage()
        
        -- Find the earliest missing narrative chapter to ensure we recover it (Repair logic)
        local first_missing_page = last_fetch_page
        if is_update then
            local toc = self.ui.document:getToc() or {}
            
            -- OMNIBUS OPTIMIZATION: Instead of checking the whole book, 
            -- find the 3 most recent narrative chapters before the current page.
            local candidate_chapters = {}
            for i = #toc, 1, -1 do
                local entry = toc[i]
                if entry.page and entry.page <= current_page then
                    if not self:isNonNarrativeChapter(entry.title) then
                        table.insert(candidate_chapters, entry)
                        if #candidate_chapters >= 3 then break end
                    end
                end
            end
            
            for _, entry in ipairs(candidate_chapters) do
                local norm = self:normalizeChapterName(entry.title)
                local found = false
                for _, ev in ipairs(self.timeline or {}) do
                    -- Match by title and page for omnibus support
                    if self:normalizeChapterName(ev.chapter or "") == norm then
                        if not ev.page or ev.page == entry.page then
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    -- This chapter is missing! Start extraction from here to recover it.
                    if not first_missing_page or entry.page < first_missing_page then
                        first_missing_page = entry.page
                        self:log("XRayPlugin: Repair mode active: recovering missing chapter '" .. tostring(entry.title) .. "' starting at page " .. tostring(entry.page))
                    end
                end
            end
        end

        -- 1b. First heavy extraction: recent book text (for context / frequency scoring)
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 20000, nil, current_page, first_missing_page)
        
        -- Build set of already-known chapters for smart sampling
        local known_chapters = {}
        if is_update and self.timeline then
            for _, ev in ipairs(self.timeline) do
                if ev.chapter then
                    known_chapters[self:normalizeChapterName(ev.chapter)] = true
                end
            end
        end
        
        -- Yield to the UI between the two heavy extraction calls.
        -- getDetailedChapterSamples iterates every TOC chapter (200+ on an omnibus)
        -- and calls getTextFromXPointer per chapter, which can take several seconds.
        -- Yielding here keeps the reader responsive (page turns, etc.).
        UIManager:scheduleIn(0, function()
            if is_cancelled then return end
            if not self.ui or not self.ui.document then return end

            -- 1c. Second heavy extraction: per-chapter samples for AI prompt
            local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(self.ui, 200, 150000, reading_percent == 100, first_missing_page, known_chapters)
            local annots = self.chapter_analyzer:getAnnotationsForAnalysis(self.ui)
        
            if (not book_text or #book_text < 10) and not samples then
                if wait_msg then UIManager:close(wait_msg) end
                if not is_silent then
                    UIManager:show(InfoMessage:new{ text = "Error: Could not extract book text.", timeout = 5 })
                end
                self:log("XRayPlugin: Text extraction failed" .. (is_silent and " (silent)" or ""))
                return
            end
        
            local context = { 
                reading_percent = reading_percent, 
                spoiler_free = reading_percent < 100, 
                filename = self.ui.document.file:match("([^/\\]+)$"), 
                series = props.series or props.Series, 
                chapter_samples = samples, 
                chapter_titles = chapter_titles,
                annotations = annots, 
                book_text = book_text,
                -- For merge fetches, pass existing data so AI only returns new information
                existing_characters = is_update and self.characters or nil,
                existing_locations = is_update and self.locations or nil,
                existing_historical_figures = is_update and self.historical_figures or nil,
            }
            
            -- 2. AI Request
            if is_silent then
                local req_params, err_code, err_msg = self.ai_helper:buildComprehensiveRequest(title, author, context)
                if not req_params then
                    self:log("XRayPlugin: Failed to build async request: " .. tostring(err_msg))
                    self.bg_fetch_active = false
                    return
                end
                
                local DataStorage = require("datastorage")
                local result_file = DataStorage:getSettingsDir() .. "/xray/bg_fetch_" .. tostring(os.time()) .. ".json"
                local started = self.ai_helper:makeRequestAsync(req_params, result_file)
                if started then
                    self:pollBackgroundFetch(result_file, title, author, book_text, is_update, current_page)
                else
                    self.bg_fetch_active = false
                    self:log("XRayPlugin: Failed to start async background fetch")
                end
                return
            end

            self.ai_helper:setTrapWidget(wait_msg)
            local final_book_data, error_code, error_msg = self.ai_helper:getBookDataComprehensive(title, author, nil, context)
            self.ai_helper:resetTrapWidget()

            if wait_msg then UIManager:close(wait_msg) end
            if is_cancelled or error_code == "USER_CANCELLED" then return end

            if not final_book_data then
                local error_dialog
                local ButtonDialog = require("ui/widget/buttondialog")
                error_dialog = ButtonDialog:new{ title = self.loc:t("error_fetch_title") or "Fetch Failed", text = error_msg or self.loc:t("error_fetch_desc") or "Failed to fetch data.", buttons = {{{ text = self.loc:t("ok"), callback = function() UIManager:close(error_dialog) end }}} }
                UIManager:show(error_dialog)
                return
            end

            self:finalizeXRayData(final_book_data, title, author, book_text, is_update, false, current_page)
        end) -- end scheduleIn(0) yield
    end)
end

function XRayPlugin:pollBackgroundFetch(result_file, title, author, book_text, is_update, current_page)
    local poll_count = 0
    local function check()
        -- Ensure we are still in a valid state
        if not self.ui or not self.ui.document then
            self:log("XRayPlugin: Polling aborted (document closed)")
            os.remove(result_file)
            self.bg_fetch_active = false
            return
        end

        poll_count = poll_count + 1
        local data, err_code, err_msg = self.ai_helper:checkAsyncResult(result_file)
        
        if data == nil then
            -- Still pending
            if poll_count < 120 then -- 4 minutes max for background
                UIManager:scheduleIn(2, check)
            else
                self:log("XRayPlugin: Background fetch timed out")
                os.remove(result_file)
                self.bg_fetch_active = false
            end
        elseif data == false then
            -- Failed
            self.bg_fetch_active = false
            self:log("XRayPlugin: Background fetch failed: " .. tostring(err_msg))
        else
            -- Success
            self.bg_fetch_active = false
            self:finalizeXRayData(data, title, author, book_text, is_update, true, current_page)
        end
    end
    UIManager:scheduleIn(2, check)
end

function XRayPlugin:finalizeXRayData(final_book_data, title, author, book_text, is_update, is_silent, current_page)
    final_book_data.book_title = title
    final_book_data.author = author

    -- Frequency Sorting
    final_book_data.characters = self:sortDataByFrequency(final_book_data.characters, book_text, "name")
    final_book_data.historical_figures = self:sortDataByFrequency(final_book_data.historical_figures, book_text, "name")
    final_book_data.locations = self:sortDataByFrequency(final_book_data.locations, book_text, "name")

    -- Filter non-narrative timeline entries the AI may have hallucinated
    if final_book_data.timeline then
        local filtered_timeline = {}
        for _, ev in ipairs(final_book_data.timeline) do
            if not self:isNonNarrativeChapter(ev.chapter) then
                table.insert(filtered_timeline, ev)
            else
                self:log("XRayPlugin: Filtered non-narrative timeline entry: " .. tostring(ev.chapter))
            end
        end
        final_book_data.timeline = filtered_timeline
    end

    if is_update then
        -- Ensure tables exist before attempting to merge/insert
        self.characters = self.characters or {}
        self.historical_figures = self.historical_figures or {}
        self.locations = self.locations or {}
        self.timeline = self.timeline or {}

        -- Merge characters
        for _, new_char in ipairs(final_book_data.characters or {}) do
            local found = false
            for _, existing_char in ipairs(self.characters) do
                if existing_char.name:lower() == new_char.name:lower() then
                    existing_char.role = new_char.role
                    -- Replace existing description with the AI's rewritten cohesive summary
                    if new_char.description and new_char.description ~= "" then
                        existing_char.description = new_char.description
                    end
                    found = true
                    break
                end
            end
            if not found then table.insert(self.characters, new_char) end
        end
        -- Dedup then re-sort the entire character list by frequency in the current context
        self.characters = self:deduplicateByName(self.characters, "name")
        if book_text and #book_text > 0 then
            self:sortDataByFrequency(self.characters, book_text, "name")
        end
        -- Merge historical figures
        for _, new_fig in ipairs(final_book_data.historical_figures or {}) do
            local found = false
            for _, existing_fig in ipairs(self.historical_figures or {}) do
                if existing_fig.name:lower() == new_fig.name:lower() then
                    if new_fig.biography and new_fig.biography ~= "" then
                        existing_fig.biography = new_fig.biography
                    end
                    existing_fig.role = new_fig.role
                    found = true
                    break
                end
            end
            if not found then table.insert(self.historical_figures, new_fig) end
        end
        self.historical_figures = self:deduplicateByName(self.historical_figures, "name")
        -- Merge locations
        for _, new_loc in ipairs(final_book_data.locations or {}) do
            local found = false
            for _, existing_loc in ipairs(self.locations or {}) do
                if existing_loc.name:lower() == new_loc.name:lower() then
                    if new_loc.description and new_loc.description ~= "" then
                        existing_loc.description = new_loc.description
                    end
                    found = true
                    break
                end
            end
            if not found then table.insert(self.locations, new_loc) end
        end
        self.locations = self:deduplicateByName(self.locations, "name")
        -- Merge timeline: duplicate = same chapter name AND same page.
        -- If either event has no page yet, treat as distinct to preserve omnibus chapters.
        local toc = self.ui.document:getToc()
        -- Assign TOC pages to incoming events before dedup check.
        -- allow_findtext=true: this is freshly-fetched AI data so document search is OK.
        self:assignTimelinePages(final_book_data.timeline or {}, toc, true)
        for _, new_event in ipairs(final_book_data.timeline or {}) do
            local found = false
            local new_norm = self:normalizeChapterName(new_event.chapter or "")
            for _, existing_event in ipairs(self.timeline or {}) do
                local exist_norm = self:normalizeChapterName(existing_event.chapter or "")
                if new_norm == exist_norm then
                    -- Both pages must be present and equal to count as a duplicate
                    if new_event.page and existing_event.page and
                       tonumber(new_event.page) == tonumber(existing_event.page) then
                        found = true
                        break
                    end
                end
            end
            if not found then table.insert(self.timeline, new_event) end
        end
        -- Sort the merged timeline chronologically
        self:sortTimelineByTOC(self.timeline)
    else
        self.characters = final_book_data.characters
        self.historical_figures = final_book_data.historical_figures
        self.locations = final_book_data.locations
        self.timeline = final_book_data.timeline
        -- Assign TOC pages and sort — must run for initial fetches too,
        -- since the AI returns chapters in arbitrary order.
        -- allow_findtext=true: this is freshly-fetched AI data so document search is OK.
        local toc = self.ui.document:getToc()
        self:assignTimelinePages(self.timeline or {}, toc, true)
        self:sortTimelineByTOC(self.timeline)
    end

    -- If we don't have author info in memory, check if the cache already has it
    -- so a character merge/update doesn't accidentally wipe a previously fetched author bio.
    if not self.author_info then
        if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
        local existing = self.cache_manager:loadCache(self.ui.document.file)
        if existing and existing.author_info then
            self.author_info = existing.author_info
        end
    end

    local updated_data = {
        book_title = title,
        author = author,
        characters = self.characters,
        historical_figures = self.historical_figures,
        locations = self.locations,
        timeline = self.timeline,
        author_info = self.author_info,
        last_fetch_page = current_page
    }
    
    self.book_data = updated_data

    if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
    local cache_saved = self.cache_manager:saveCache(self.ui.document.file, updated_data)

    if is_silent then
        self:log(string.format("XRayPlugin: Silent merge complete - Chars: %d, Locs: %d, Events: %d, Cache: %s",
            #self.characters, #self.locations, #self.timeline,
            cache_saved and "saved" or "failed"))
        -- Testing notification: brief toast
        UIManager:show(InfoMessage:new{ text = "✓ X-Ray background update complete.", timeout = 2 })
    else
        local summary = string.format("AI Fetch Complete!\n\nCharacters: %d\nLocations: %d\nEvents: %d\n\n%s", 
            #self.characters, #self.locations, #self.timeline,
            cache_saved and "✓ Cache updated." or "✗ Cache failed.")

        local success_dialog
        local ButtonDialog = require("ui/widget/buttondialog")
        success_dialog = ButtonDialog:new{ title = self.loc:t("fetch_successful") or "Fetch successful", text = summary, buttons = {{{ text = self.loc:t("ok"), callback = function() 
            UIManager:close(success_dialog) 
        end }}} }
        UIManager:show(success_dialog)
    end
end

function XRayPlugin:fetchMoreCharacters()
    require("ui/network/manager"):runWhenOnline(function() 
        if not self.ai_helper then
            local AIHelper = require("xray_aihelper")
            self.ai_helper = AIHelper
            self.ai_helper:init(self.path)
        end
        local props = self.ui.document:getProps() or {}
        local title = sanitizeMetadata(props.title)
        local author = sanitizeMetadata(props.authors)
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        -- Capture the current menu widget NOW, before the async fetch starts.
        -- self.char_menu may be nilled by close_callback when wait_msg appears on top,
        -- so we need a local reference to close the old menu reliably at the end.
        local menu_to_close = self.char_menu
        self.char_menu = nil

        local wait_msg
        local is_cancelled = false
        wait_msg = InfoMessage:new{ text = (self.loc:t("fetching_ai") or "Fetching from %s...") .. "\n\n" .. title .. "\n\nExtracting additional characters...", timeout = 120 }
        UIManager:show(wait_msg)
        
        UIManager:scheduleIn(0.5, function()
            if is_cancelled then return end
            if not self.chapter_analyzer then self.chapter_analyzer = require("xray_chapteranalyzer"):new() end
            
            -- EVEN SAMPLING: Divide the readable range into equal segments
            -- and sample one window from each, covering the whole book uniformly
            local current_page = self.ui:getCurrentPage()
            local pages_per_sample = 20
            local chars_per_sample = 10000
            local num_samples = 6
            
            -- Track call count to shift windows on each invocation
            self.more_chars_call_count = (self.more_chars_call_count or 0) + 1
            local call_num = self.more_chars_call_count
            local offset = (call_num - 1) * pages_per_sample
            self:log("XRayPlugin: More chars call #" .. call_num .. " (offset: " .. offset .. " pages)")
            
            -- Divide readable range into equal segments
            local readable_pages = math.max(1, current_page)
            local segment_size = math.floor(readable_pages / num_samples)
            if segment_size < pages_per_sample then segment_size = pages_per_sample end
            
            local text_parts = {}
            for i = 0, num_samples - 1 do
                local segment_start = i * segment_size
                local sample_start = math.min(segment_start + offset, readable_pages - pages_per_sample)
                sample_start = math.max(1, sample_start)
                
                -- Wrap around within the segment if the offset pushes past the segment boundary
                local segment_end = (i + 1) * segment_size
                if sample_start >= segment_end and i < num_samples - 1 then
                    sample_start = segment_start + ((offset) % segment_size)
                    sample_start = math.max(1, math.min(sample_start, readable_pages - pages_per_sample))
                end
                
                if sample_start <= current_page then
                    local end_page = math.min(sample_start + pages_per_sample, current_page)
                    local sample = self.chapter_analyzer:getTextFromPageRange(self.ui, sample_start, end_page, chars_per_sample)
                    if sample and #sample > 100 then
                        table.insert(text_parts, "[SECTION " .. (i + 1) .. "]\n" .. sample)
                        self:log("XRayPlugin: More chars sample " .. (i + 1) .. " pages " .. sample_start .. "-" .. end_page .. ": " .. #sample .. " chars")
                    end
                end
            end
            local book_text = table.concat(text_parts, "\n\n---\n\n")
            
            local exclude_list = {}
            for _, char in ipairs(self.characters or {}) do
                table.insert(exclude_list, char.name)
            end
            
            local context = { 
                reading_percent = reading_percent, 
                filename = self.ui.document.file:match("([^/\\]+)$"), 
                series = props.series or props.Series, 
                book_text = book_text,
                exclude_characters = table.concat(exclude_list, ", ")
            }
            
            self.ai_helper:setTrapWidget(wait_msg)
            local more_data, error_code, error_msg = self.ai_helper:getMoreCharacters(title, author, nil, context)
            self.ai_helper:resetTrapWidget()
            
            if wait_msg then UIManager:close(wait_msg) end
            if is_cancelled or error_code == "USER_CANCELLED" then return end
            
            if not more_data or not more_data.characters then
                local error_dialog
                local ButtonDialog = require("ui/widget/buttondialog")
                error_dialog = ButtonDialog:new{ title = "Fetch Failed", text = error_msg or "Failed to fetch more characters.", buttons = {{{ text = self.loc:t("ok"), callback = function() UIManager:close(error_dialog) end }}} }
                UIManager:show(error_dialog)
                return
            end
            
            local new_count = 0
            for _, new_char in ipairs(more_data.characters) do
                local found = false
                for _, existing_char in ipairs(self.characters or {}) do
                    if existing_char.name:lower() == new_char.name:lower() then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(self.characters, new_char)
                    new_count = new_count + 1
                end
            end
            
            -- Re-sort by frequency based on the newly extracted samples
            if book_text and #book_text > 0 then
                self:sortDataByFrequency(self.characters, book_text, "name")
            end
            
            -- Save to cache
            if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
            local existing_cache = self.cache_manager:loadCache(self.ui.document.file) or {}
            local updated_data = {
                book_title = title,
                author = author,
                characters = self.characters,
                historical_figures = self.historical_figures,
                locations = self.locations,
                timeline = self.timeline,
                author_info = self.author_info or existing_cache.author_info
            }
            self.cache_manager:saveCache(self.ui.document.file, updated_data)
            
            UIManager:show(InfoMessage:new{ text = string.format("Added %d new characters!", new_count), timeout = 3 })

            -- Close the old menu using the captured local reference, which is immune
            -- to close_callback having nilled self.char_menu during the wait.
            if menu_to_close then
                UIManager:close(menu_to_close)
            end
            self:showCharacters()
        end)
    end)
end

function XRayPlugin:fetchAuthorInfo()
    if not self.ai_helper then
        local AIHelper = require("xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)
    local wait_msg
    local is_cancelled = false
    wait_msg = InfoMessage:new{ text = self.loc:t("fetching_author", "AI") .. "\n\n" .. title .. " - " .. author .. "\n\n" .. self.loc:t("fetching_wait"), timeout = 120 }
    UIManager:show(wait_msg)
    UIManager:scheduleIn(0.5, function()
        if is_cancelled then return end
        
        if not self.chapter_analyzer then
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            self.chapter_analyzer = ChapterAnalyzer:new()
        end
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 1000, nil, self.ui:getCurrentPage())
        local context = { book_text = book_text }
        
        self.ai_helper:setTrapWidget(wait_msg)
        local author_data, error_code, error_msg = self.ai_helper:getAuthorData(title, author, nil, context)
        self.ai_helper:resetTrapWidget()
        
        if wait_msg then UIManager:close(wait_msg) end
        if is_cancelled or error_code == "USER_CANCELLED" then return end

        if not author_data then
            local error_dialog
            local ButtonDialog = require("ui/widget/buttondialog")
            error_dialog = ButtonDialog:new{ title = self.loc:t("error_author_fetch_title") or "Error: Author Fetch", text = (error_msg or self.loc:t("error_author_fetch_desc") or "Failed to fetch author info.") .. "\n\n(See crash.log in root for details)", buttons = {{{ text = self.loc:t("ok"), callback = function() UIManager:close(error_dialog) end }}} }
            UIManager:show(error_dialog)
            return
        end
        self.author_info = { 
            name = sanitizeMetadata(author_data.author or author), 
            description = sanitizeMetadata(author_data.author_bio or "No biography available."), 
            birthDate = sanitizeMetadata(author_data.author_birth or "---"), 
            deathDate = sanitizeMetadata(author_data.author_death or "---") 
        }
        if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
        local cache = self.cache_manager:loadCache(self.ui.document.file) or {}
        cache.author_info = self.author_info
        cache.author = self.author_info.name; cache.author_bio = self.author_info.description; cache.author_birth = self.author_info.birthDate; cache.author_death = self.author_info.deathDate
        self.cache_manager:saveCache(self.ui.document.file, cache)
        self:showAuthorInfo()
    end)
end

function XRayPlugin:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == "No biography available." then
        local ButtonDialog = require("ui/widget/buttondialog")
        local ask_dialog
        ask_dialog = ButtonDialog:new{ title = self.loc:t("menu_fetch_author") or "Fetch Author Info", text = self.loc:t("no_author_data_fetch"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(ask_dialog) end }, { text = self.loc:t("fetch_button") or "Fetch", is_enter_default = true, callback = function() UIManager:close(ask_dialog); UIManager:nextTick(function() self:fetchAuthorInfo() end) end }}} }
        UIManager:show(ask_dialog); return
    end
    local lines = { "NAME: " .. (self.author_info.name or "Unknown"), "BORN: " .. (self.author_info.birthDate or "---"), "DIED: " .. (self.author_info.deathDate or "---"), "", "BIOGRAPHY:", (self.author_info.description or "No biography available.") }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 30 })
end

function XRayPlugin:showLocations()
    if not self.locations or #self.locations == 0 then 
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return 
    end
    local items = {}
    for _, loc in ipairs(self.locations) do 
        if type(loc) == "table" then
            local name = loc.name or "???"
            local desc = loc.description or ""
            table.insert(items, { 
                text = name, 
                callback = function() 
                    UIManager:show(InfoMessage:new{ 
                        text = name .. "\n\n" .. desc, 
                        timeout = 10 
                    }) 
                end 
            })
        end
    end
    
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return
    end
    
    UIManager:show(Menu:new{ title = self.loc:t("menu_locations"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    local ConfirmBox = require("ui/widget/confirmbox")
    local version = meta.version or "?.?.?"
    local description = tostring(meta.description or "")

    local body = (meta.fullname or "X-Ray") .. " v" .. version .. "\n\n" .. description

    UIManager:show(ConfirmBox:new{
        text = body,
        icon = "lightbulb",
        ok_text = self.loc:t("updater_check") or "Check for Updates",
        cancel_text = self.loc:t("close") or "Close",
        ok_callback = function()
            local updater = require("xray_updater")
            updater.checkForUpdates(self.loc)
        end,
    })
end

function XRayPlugin:clearCache()
    if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}; self.locations = {}; self.timeline = {}; self.historical_figures = {}; self.author_info = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function XRayPlugin:clearLogs()
    XRayLogger:clear()
    UIManager:show(InfoMessage:new{ text = self.loc:t("logs_cleared") or "Logs cleared!", timeout = 3 })
end

function XRayPlugin:toggleXRayMode()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_xray_mode") or "X-Ray Mode Settings",
            text = self.loc:t("xray_mode_desc"),
            buttons = {
                {
                    {
                        text = (self.xray_mode_enabled and "[✓] " or "[  ] ") .. (self.loc:t("xray_enabled_label") or "Enabled"),
                        callback = function()
                            self.xray_mode_enabled = true
                            if self.ai_helper then self.ai_helper:saveSettings({ xray_mode_enabled = true }) end
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = (not self.xray_mode_enabled and "[✓] " or "[  ] ") .. (self.loc:t("xray_disabled_label") or "Disabled"),
                        callback = function()
                            self.xray_mode_enabled = false
                            if self.ai_helper then self.ai_helper:saveSettings({ xray_mode_enabled = false }) end
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("xray_mode_desc"),
                                timeout = 30
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function XRayPlugin:showTimeline()
    if not self.timeline or #self.timeline == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 }); return end
    -- Sort by the page number stamped at fetch time (persisted in cache).
    -- allow_findtext=true: this is user-initiated so a brief document search is acceptable;
    -- it also repairs any legacy cached events that are still missing a page number.
    local toc = self.ui.document:getToc()
    self:assignTimelinePages(self.timeline, toc, true)
    self:sortTimelineByTOC(self.timeline)
    local items = {}
    for _, ev in ipairs(self.timeline) do table.insert(items, { text = (ev.chapter or "") .. ": " .. (ev.event or ""), callback = function() UIManager:show(InfoMessage:new{ text = (ev.event or ""), timeout = 10 }) end }) end
    UIManager:show(Menu:new{ title = self.loc:t("menu_timeline"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showHistoricalFigures()
    if not self.historical_figures or #self.historical_figures == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 }); return end
    local items = {}
    for _, fig in ipairs(self.historical_figures) do table.insert(items, { text = (fig.name or "???"), callback = function() UIManager:show(InfoMessage:new{ text = (fig.name or "") .. "\n\n" .. (fig.biography or ""), timeout = 15 }) end }) end
    UIManager:show(Menu:new{ title = self.loc:t("menu_historical_figures"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showQuickXRayMenu() self:showFullXRayMenu() end
function XRayPlugin:showFullXRayMenu()
    if self.xray_menu then UIManager:close(self.xray_menu); self.xray_menu = nil end
    self.xray_menu = Menu:new{ 
        title = self.loc:t("menu_xray") or "X-Ray", 
        item_table = self:getSubMenuItems(), 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight() 
    }
    UIManager:show(self.xray_menu) 
end

function XRayPlugin:getAPIKeySelectionMenu(provider, provider_name)
    local config_key = self.ai_helper.config_keys[provider]
    
    local menu_items = {
        {
            text = "Use key from config.lua: " .. (config_key and #config_key > 0 and config_key or "(Not set)"),
            checked_func = function() 
                return not self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = false })
                self.ai_helper:init(self.path)
                UIManager:setDirty(nil, "ui")
            end
        },
        {
            text = "Enter UI override key: " .. (self.ai_helper.settings[provider .. "_api_key"] or "(Not set)"),
            checked_func = function() 
                return self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                local ui_key = self.ai_helper.settings[provider .. "_api_key"]
                
                -- If we have a UI key but it's not currently active, let's just activate it
                if ui_key and #ui_key > 0 and not self.ai_helper.providers[provider].ui_key_active then
                    self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = true })
                    self.ai_helper:init(self.path)
                    UIManager:setDirty(nil, "ui")
                    return
                end

                local InputDialog = require("ui/widget/inputdialog")
                local input_dialog
                input_dialog = InputDialog:new{
                    title = provider_name .. " API Key",
                    input = ui_key or "",
                    buttons = {
                        {
                            { text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end },
                            { text = self.loc:t("save"), is_enter_default = true, callback = function()
                                local key = input_dialog:getInputText()
                                UIManager:close(input_dialog)
                                if key and #key > 0 then
                                    self.ai_helper:setAPIKey(provider, key)
                                    UIManager:setDirty(nil, "ui")
                                end
                            end }
                        }
                    }
                }
                UIManager:show(input_dialog)
                input_dialog:onShowKeyboard()
            end
        }
    }
    return menu_items
end

function XRayPlugin:getAIModelSelectionMenu(setting_type)
    local models = {
        { name = "Gemini Flash (gemini-2.5-flash) - free", provider = "gemini", id = "gemini-2.5-flash" },
        { name = "Gemini Flash-Lite (gemini-2.5-flash-lite) - free", provider = "gemini", id = "gemini-2.5-flash-lite" },
        { name = "Gemini Pro (gemini-1.5-pro) - paid", provider = "gemini", id = "gemini-1.5-pro" },
        { name = "ChatGPT Mini (gpt-4o-mini) - paid", provider = "chatgpt", id = "gpt-4o-mini" },
        { name = "ChatGPT (gpt-4o) - paid", provider = "chatgpt", id = "gpt-4o" },
    }
    
    local menu_items = {}
    for _, m in ipairs(models) do
        table.insert(menu_items, {
            text = m.name,
            checked_func = function()
                local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                if not current then return false end
                return current.provider == m.provider and current.model == m.id
            end,
            callback = function()
                self.ai_helper:setUnifiedModel(setting_type, m.provider, m.id)
                UIManager:setDirty(nil, "ui")
            end
        })
    end
    
    table.insert(menu_items, { separator = true })
    table.insert(menu_items, {
        text = "Enter custom model...",
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
            input_dialog = InputDialog:new{
                title = "Custom " .. setting_type:gsub("^%l", string.upper) .. " Model",
                input = current and current.model or "",
                input_hint = "e.g., gemini-1.5-pro",
                buttons = {
                    {
                        {
                            text = self.loc:t("cancel") or "Cancel",
                            callback = function() UIManager:close(input_dialog) end
                        },
                        {
                            text = self.loc:t("save") or "Save",
                            is_enter_default = true,
                            callback = function()
                                local custom_model = input_dialog:getInputText()
                                if custom_model and #custom_model > 0 then
                                    local provider = string.find(custom_model, "gpt") and "chatgpt" or "gemini"
                                    self.ai_helper:setUnifiedModel(setting_type, provider, custom_model)
                                    UIManager:show(InfoMessage:new{ text = setting_type:gsub("^%l", string.upper) .. " AI set to " .. custom_model, timeout = 3 })
                                    UIManager:setDirty(nil, "ui")
                                end
                                UIManager:close(input_dialog)
                            end
                        }
                    }
                }
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end
    })
    
    return menu_items
end


function XRayPlugin:findCharacterByName(word)
    if not self.characters or not word then return nil end
    local word_lower = string.lower(word)
    for _, char in ipairs(self.characters) do
        local name_lower = string.lower(char.name or "")
        if name_lower == word_lower or string.find(name_lower, word_lower, 1, true) then
            return char
        end
    end
    return nil
end

function XRayPlugin:showCharacterSearch()
    if not self.characters or #self.characters == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("search_character_title"), input = "", input_hint = self.loc:t("search_hint"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("search_button"), is_enter_default = true, callback = function() local search_text = input_dialog:getInputText(); UIManager:close(input_dialog); if search_text and #search_text > 0 then local found_char = self:findCharacterByName(search_text); if found_char then self:showCharacterDetails(found_char) else UIManager:show(InfoMessage:new{ text = self.loc:t("character_not_found", search_text), timeout = 3 }) end end end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function XRayPlugin:showConfigSummary()
    local text = "--- Current Configuration ---\n\n"
    
    local primary = self.ai_helper.settings.primary_ai
    local secondary = self.ai_helper.settings.secondary_ai
    
    text = text .. "Primary AI:\n"
    if primary then text = text .. "  Provider: " .. primary.provider .. "\n  Model: " .. primary.model .. "\n\n" else text = text .. "  Default (Gemini)\n\n" end
    
    text = text .. "Secondary AI:\n"
    if secondary then text = text .. "  Provider: " .. secondary.provider .. "\n  Model: " .. secondary.model .. "\n\n" else text = text .. "  Default (Gemini)\n\n" end
    
    local function add(p, n)
        local c = self.ai_helper.providers[p]
        text = text .. n .. " API Key: " .. (c.api_key and "SET" or "NOT SET") .. "\n"
    end
    add("gemini", "Google Gemini"); add("chatgpt", "ChatGPT")
    
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end

function XRayPlugin:checkWeeklyUpdate()
    if not self.ai_helper or not self.ai_helper.settings then return end
    
    local last_check = self.ai_helper.settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    
    if (now - last_check) > week_seconds then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isOnline() then
            self:log("XRayPlugin: Triggering weekly silent update check")
            self.ai_helper:saveSettings({ last_update_check = now })
            local updater = require("xray_updater")
            updater.checkSilentForUpdates(self.loc)
        else
            self:log("XRayPlugin: Skipping weekly update check (offline)")
        end
    end
end

return XRayPlugin
