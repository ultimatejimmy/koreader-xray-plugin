-- X-Ray Plugin for KOReader v2.0.0

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Trapper = require("ui/trapper")
local logger = require("logger")
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
    self.auto_fetch_enabled = (self.ai_helper.settings and
        self.ai_helper.settings.auto_fetch_on_chapter == true) or false

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
    if self.ai_helper and self.ai_helper.log then
        self.ai_helper:log(msg)
    end
end

function XRayPlugin:onReaderReady()
    self:autoLoadCache()
    -- Reset per-session chapter fetch tracking
    self.last_auto_chapter = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false
end

function XRayPlugin:onPageUpdate(pageno)
    if not self.auto_fetch_enabled then return end
    if not self.xray_mode_enabled then return end
    if not self.ui or not self.ui.document then return end

    -- Resolve current chapter title from TOC
    local toc = self.ui.document:getToc()
    if not toc or #toc == 0 then return end

    local chapter_title = nil
    for _, entry in ipairs(toc) do
        if entry.page and entry.page <= pageno then
            chapter_title = entry.title
        else
            break
        end
    end
    if not chapter_title then return end

    -- Already fetched this chapter this session?
    if self.chapters_fetched[chapter_title] then return end

    -- Same chapter as before (no change)?
    if chapter_title == self.last_auto_chapter then return end
    self.last_auto_chapter = chapter_title

    -- Debounce: ignore if a fetch is already scheduled
    if self.bg_fetch_pending or self.bg_fetch_active then return end
    self.bg_fetch_pending = true

    -- Wait 2s for the reader to settle on the new chapter before fetching
    UIManager:scheduleIn(2, function()
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end)
end

function XRayPlugin:triggerBackgroundMergeFetch(chapter_title)
    if self.chapters_fetched[chapter_title] or self.bg_fetch_active then return end
    if not self.ui or not self.ui.document then return end

    -- SILENT NETWORK CHECK: use isOnline() instead of runWhenOnline to avoid "white box" connecting dialogs
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isOnline() then
        local current_page = self.ui:getCurrentPage()
        local total_pages = self.ui.document:getPageCount()
        if not total_pages or total_pages == 0 then return end
        local reading_percent = math.floor((current_page / total_pages) * 100)
        
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
        
        self:log("XRayPlugin: Auto-merge fetch for chapter: " .. tostring(chapter_title))
        self:continueWithFetch(reading_percent, true, last_fetch_page, true) -- is_update=true, is_silent=true
        self.chapters_fetched[chapter_title] = true
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
        },
        {
            text = self.loc:t("menu_fetch_author") or "Fetch Author Info (AI)",
            keep_menu_open = true,
            callback = function() self:fetchAuthorInfo() end,
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
                    text = "Auto-update on new chapter",
                    keep_menu_open = true,
                    checked_func = function()
                        return self.auto_fetch_enabled == true
                    end,
                    callback = function()
                        self.auto_fetch_enabled = not self.auto_fetch_enabled
                        self.ai_helper:saveSettings({ auto_fetch_on_chapter = self.auto_fetch_enabled })
                    end,
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
                    text = self.loc:t("updater_check") or "Check for Updates",
                    keep_menu_open = true,
                    callback = function()
                        local updater = require("xray_updater")
                        updater.checkForUpdates(self.loc)
                    end,
                    separator = true,
                },
                {
                    text = self.loc:t("menu_about"),
                    keep_menu_open = true,
                    callback = function() self:showAbout() end,
                }
            }
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
    if not list or #list == 0 or not text then return list end
    local lower_text = string.lower(text)
    for _, item in ipairs(list) do
        local name = item[key or "name"]
        if name then
            local pattern = string.lower(name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
            local _, count = string.gsub(lower_text, pattern, "")
            item._frequency = count
        end
    end
    table.sort(list, function(a, b) return (a._frequency or 0) > (b._frequency or 0) end)
    return list
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
    UIManager:show(Menu:new{ title = self.loc:t("menu_characters") .. " (" .. #self.characters .. ")", item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
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
function XRayPlugin:normalizeChapterName(name)
    if not name then return "" end
    local s = name:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Replace written-out numbers with digits using word boundaries
    for word, num in pairs(word_to_num) do
        s = s:gsub("%f[%a]" .. word .. "%f[%A]", tostring(num))
    end
    -- Strip common prefixes like "chapter" so "chapter 13" and "13" both become "13"
    s = s:gsub("^chapter%s*", ""):gsub("^ch%.?%s*", "")
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

local function sanitizeMetadata(val)
    if type(val) == "string" then return val
    elseif type(val) == "table" then return table.concat(val, ", ")
    else return "Unknown" end
end

function XRayPlugin:continueWithFetch(reading_percent, is_update, last_fetch_page, is_silent)
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

        -- 1. Extraction (Main Thread)
        local current_page = self.ui:getCurrentPage()
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 20000, nil, current_page, last_fetch_page)
        local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(self.ui, 200, 150000, reading_percent == 100, last_fetch_page)
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
                return
            end
            
            local DataStorage = require("datastorage")
            local result_file = DataStorage:getSettingsDir() .. "/xray/bg_fetch_" .. tostring(os.time()) .. ".json"
            self.bg_fetch_active = true
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
        -- Merge characters
        for _, new_char in ipairs(final_book_data.characters or {}) do
            local found = false
            for _, existing_char in ipairs(self.characters or {}) do
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
        -- Merge timeline (append only if chapter not found)
        for _, new_event in ipairs(final_book_data.timeline or {}) do
            local found = false
            local new_norm = self:normalizeChapterName(new_event.chapter or "")
            for _, existing_event in ipairs(self.timeline or {}) do
                local exist_norm = self:normalizeChapterName(existing_event.chapter or "")
                if new_norm == exist_norm then
                    found = true
                    break
                end
            end
            if not found then table.insert(self.timeline, new_event) end
        end
    else
        self.characters = final_book_data.characters
        self.historical_figures = final_book_data.historical_figures
        self.locations = final_book_data.locations
        self.timeline = final_book_data.timeline
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
        
        local wait_msg
        local is_cancelled = false
        wait_msg = InfoMessage:new{ text = (self.loc:t("fetching_ai") or "Fetching from %s...") .. "\n\n" .. title .. "\n\nExtracting additional characters...", timeout = 120 }
        UIManager:show(wait_msg)
        
        UIManager:scheduleIn(0.5, function()
            if is_cancelled then return end
            if not self.chapter_analyzer then self.chapter_analyzer = require("xray_chapteranalyzer"):new() end
            
            local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 20000, nil, self.ui:getCurrentPage())
            local samples, _ = self.chapter_analyzer:getDetailedChapterSamples(self.ui, 200, 150000, reading_percent == 100)
            
            local exclude_list = {}
            for _, char in ipairs(self.characters or {}) do
                table.insert(exclude_list, char.name)
            end
            
            local context = { 
                reading_percent = reading_percent, 
                filename = self.ui.document.file:match("([^/\\]+)$"), 
                series = props.series or props.Series, 
                chapter_samples = samples, 
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
            
            -- Save to cache
            local updated_data = {
                book_title = title,
                author = author,
                characters = self.characters,
                historical_figures = self.historical_figures,
                locations = self.locations,
                timeline = self.timeline,
                author_info = self.author_info
            }
            if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
            self.cache_manager:saveCache(self.ui.document.file, updated_data)
            
            UIManager:show(InfoMessage:new{ text = string.format("Added %d new characters!", new_count), timeout = 3 })
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
    UIManager:show(InfoMessage:new{ text = (meta.fullname or "X-Ray") .. " v" .. (meta.version or "?.?.?") .. "\n\n" .. (meta.description or ""), timeout = 15 })
end

function XRayPlugin:clearCache()
    if not self.cache_manager then self.cache_manager = require("xray_cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}; self.locations = {}; self.timeline = {}; self.historical_figures = {}; self.author_info = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
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
    input_dialog = InputDialog:new{ title = self.loc:t("search_character_title"), input = "", input_hint = self.loc:t("search_hint"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("search_button"), is_enter_default = true, callback = function() local search_text = input_dialog:getInputText(); UIManager:close(input_dialog); if search_text and #search_text > 0 then local found_char = self:findCharacterByName(search_text); if found_char then self:showCharacterDetails(found_char) else UIManager:show(InfoMessage:new{ text = string.format(self.loc:t("character_not_found"), search_text), timeout = 3 }) end end end }}} }
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

return XRayPlugin
