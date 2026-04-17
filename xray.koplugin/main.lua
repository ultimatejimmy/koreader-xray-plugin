-- X-Ray Plugin for KOReader v2.0.0

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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

    local Localization = require("localization_xray")
    self.loc = Localization
    self.loc:init(self.path)
    
    local AIHelper = require("aihelper")
    self.ai_helper = AIHelper
    self.ai_helper:init(self.path)
    self.ai_provider = self.ai_helper.default_provider or "gemini"
    
    self:log("XRayPlugin: Initialized with language: " .. self.loc:getLanguage())
    self:onDispatcherRegisterActions()
    
    if self.ui then
        self.ui:registerKeyEvents({
            ShowXRayMenu = {
                { "Alt", "X" },
                event = "ShowXRayMenu",
            },
        })
    end
    
    logger.info("XRayPlugin: Initialized with language:", self.loc:getLanguage())
end

function XRayPlugin:log(msg)
    if self.ai_helper and self.ai_helper.log then
        self.ai_helper:log(msg)
    end
end

function XRayPlugin:onReaderReady()
    self:autoLoadCache()
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
    Dispatcher:registerAction("xray_chapter_characters", {
        category = "none",
        event = "ShowXRayChapterCharacters",
        title = self.loc:t("menu_chapter_characters") or "Chapter Characters",
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
        local CacheManager = require("cachemanager")
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

function XRayPlugin:addToMainMenu(menu_items)
    local counts = self:getMenuCounts()
    
    menu_items.xray = {
        text = self.loc:t("menu_xray") or "X-Ray",
        sorting_hint = "tools",
        callback = function() self:showQuickXRayMenu() end,
        hold_callback = function() self:showFullXRayMenu() end,
        sub_item_table = {
            {
                text = self.loc:t("menu_characters") .. (counts.characters > 0 and " (" .. counts.characters .. ")" or ""),
                keep_menu_open = true,
                callback = function() self:showCharacters() end,
            },
            {
                text = self.loc:t("menu_chapter_characters"),
                keep_menu_open = true,
                callback = function() self:showChapterCharacters() end,
            },
            {
                text = self.loc:t("menu_timeline") .. (counts.timeline > 0 and " (" .. counts.timeline .. " " .. self.loc:t("events") .. ")" or ""),
                keep_menu_open = true,
                callback = function() self:showTimeline() end,
            },
            {
                text = self.loc:t("menu_historical_figures") .. (counts.historical_figures > 0 and " (" .. counts.historical_figures .. ")" or ""),
                keep_menu_open = true,
                callback = function() self:showHistoricalFigures() end,
            },
            {
                text = self.loc:t("menu_locations") .. (counts.locations > 0 and " (" .. counts.locations .. ")" or ""),
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
                text = self.loc:t("menu_fetch_author") or "Fetch Author Info (AI)",
                keep_menu_open = true,
                callback = function() self:fetchAuthorInfo() end,
                separator = true,
            },
            {
                text = self.loc:t("menu_ai_settings"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_provider_select") .. " (" .. (self.ai_provider or "gemini") .. ")", 
                        keep_menu_open = true,
                        callback = function() self:selectAIProvider() end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_gemini_key") .. " (" .. (self.ai_helper.providers.gemini.api_key and "SET" or "NOT SET") .. ")", 
                        keep_menu_open = true,
                        callback = function() self:setGeminiAPIKey() end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_chatgpt_key") .. " (" .. (self.ai_helper.providers.chatgpt.api_key and "SET" or "NOT SET") .. ")", 
                        keep_menu_open = true,
                        callback = function() self:setChatGPTAPIKey() end,
                        separator = true,
                    },
                    {
                        text = "View All Config Values", 
                        keep_menu_open = true,
                        callback = function() self:showConfigSummary() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_clear_cache"),
                keep_menu_open = true,
                callback = function() self:clearCache() end,
                separator = true,
            },
            {
                text = self.loc:t("menu_xray_mode") .. " " .. (self.xray_mode_enabled and self.loc:t("xray_mode_active") or self.loc:t("xray_mode_inactive")),
                keep_menu_open = true,
                callback = function() self:toggleXRayMode() end,
            },
            {
                text = self.loc:t("menu_language") or "Language",
                keep_menu_open = true,
                callback = function() self:showLanguageSelection() end,
                separator = true,
            },
            {
                text = self.loc:t("menu_about"),
                keep_menu_open = true,
                callback = function() self:showAbout() end,
            },
        }
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
    local items = {{ text = "[Search] " .. self.loc:t("search_character"), callback = function() self:showCharacterSearch() end }}
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
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), width = Screen:getWidth() * 0.9 })
end

function XRayPlugin:fetchFromAI()
    require("ui/network/manager"):runWhenOnline(function() self:askSpoilerPreference() end)
end

function XRayPlugin:askSpoilerPreference()
    local current_page = self.ui:getCurrentPage()
    local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
    local spoiler_menu = Menu:new{
        title = self.loc:t("spoiler_preference_title"),
        item_table = {
            { text = self.loc:t("spoiler_free_option", reading_percent), callback = function() UIManager:close(spoiler_menu); self:continueWithFetch(reading_percent) end },
            { text = self.loc:t("full_book_option"), callback = function() UIManager:close(spoiler_menu); self:continueWithFetch(100) end },
            { text = self.loc:t("cancel"), callback = function() UIManager:close(spoiler_menu) end },
        },
        is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight(),
    }
    UIManager:show(spoiler_menu)
end

function XRayPlugin:continueWithFetch(reading_percent)
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    local props = self.ui.document:getProps() or {}
    local title, author = props.title or "Unknown", props.authors or "Unknown"
    local wait_msg
    local is_cancelled = false
    wait_msg = ButtonDialog:new{ title = self.loc:t("fetching_ai", self.ai_provider or "AI"), text = title .. "\n\n" .. self.loc:t("fetching_wait") .. "\n\n" .. (self.loc:t("dont_touch") or "Do not touch the screen."), buttons = {{{ text = self.loc:t("cancel"), id = "close", callback = function() is_cancelled = true; UIManager:close(wait_msg) end }}}, close_on_touch_outside = false }
    UIManager:show(wait_msg)
    UIManager:scheduleIn(0.5, function()
        if is_cancelled then return end
        if not self.chapter_analyzer then self.chapter_analyzer = require("chapteranalyzer"):new() end
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 100000, nil, self.ui:getCurrentPage())
        local chapter_samples = self.chapter_analyzer:getDetailedChapterSamples(self.ui)
        if (not book_text or #book_text < 10) and not chapter_samples then
            if wait_msg then UIManager:close(wait_msg) end
            UIManager:show(InfoMessage:new{ text = "Error: Could not extract book text.", timeout = 5 })
            return
        end
        local context = { reading_percent = reading_percent, spoiler_free = reading_percent < 100, filename = self.ui.document.file:match("([^/\\]+)$"), series = props.series or props.Series, chapter_samples = chapter_samples, annotations = self.chapter_analyzer:getAnnotationsForAnalysis(self.ui) }
        self.ai_helper:setTrapWidget(wait_msg)
        local sections = {{ id = "character_section", name = "Characters & Figures" }, { id = "location_section", name = "Significant Locations" }, { id = "timeline_section", name = "Narrative Timeline" }}
        local final_book_data = { book_title = title, author = author, characters = {}, historical_figures = {}, locations = {}, timeline = {} }
        local results_summary = {}
        local success_count = 0
        local function fetchNext(index)
            if is_cancelled then self.ai_helper:resetTrapWidget(); if wait_msg then UIManager:close(wait_msg) end; return end
            if index > #sections then
                self.ai_helper:resetTrapWidget(); if wait_msg then UIManager:close(wait_msg) end
                
                -- Frequency Sorting
                final_book_data.characters = self:sortDataByFrequency(final_book_data.characters, book_text, "name")
                final_book_data.historical_figures = self:sortDataByFrequency(final_book_data.historical_figures, book_text, "name")
                final_book_data.locations = self:sortDataByFrequency(final_book_data.locations, book_text, "name")
                
                self.characters = final_book_data.characters; self.historical_figures = final_book_data.historical_figures; self.locations = final_book_data.locations; self.timeline = final_book_data.timeline
                if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
                local cache_saved = self.cache_manager:saveCache(self.ui.document.file, final_book_data)
                local summary_list = table.concat(results_summary, "\n• ")
                local success_message = string.format("AI Fetch Complete!\n\nBook: %s\nAuthor: %s\n\nResults:\n• %s\n\n%s\n\nDetails logged to 'xray.log' in the plugin folder.", title, author, summary_list, cache_saved and "✓ Cache updated." or "✗ Cache failed.")
                local success_dialog
                success_dialog = ButtonDialog:new{ title = (success_count > 0) and (self.loc:t("fetch_successful") or "Fetch successful") or "Fetch Failed", text = success_message, buttons = {{{ text = self.loc:t("ok"), callback = function() UIManager:close(success_dialog) end }}} }
                UIManager:show(success_dialog)
                return
            end
            local section = sections[index]
            local current_context = { reading_percent = context.reading_percent, spoiler_free = context.spoiler_free, filename = context.filename, series = context.series, annotations = context.annotations }
            if section.id == "character_section" then current_context.book_text = book_text:sub(1, 40000)
            elseif section.id == "location_section" then current_context.book_text = book_text:sub(-40000)
            elseif section.id == "timeline_section" then current_context.chapter_samples = context.chapter_samples end
            local section_data, error_code, error_msg = self.ai_helper:getBookDataSection(title, author, self.ai_provider, current_context, section.id)
            if not section_data then
                if error_code == "USER_CANCELLED" then is_cancelled = true; fetchNext(#sections + 1); return end
                table.insert(results_summary, section.name .. ": [FAILED] (" .. (error_msg or "Server Busy") .. ")")
            else
                success_count = success_count + 1
                if section.id == "character_section" then final_book_data.characters = section_data.characters or {}; final_book_data.historical_figures = section_data.historical_figures or {}
                    table.insert(results_summary, "Characters: " .. #final_book_data.characters); table.insert(results_summary, "Historical Figures: " .. #final_book_data.historical_figures)
                elseif section.id == "location_section" then final_book_data.locations = section_data.locations or {}
                    table.insert(results_summary, "Locations: " .. #final_book_data.locations)
                elseif section.id == "timeline_section" then final_book_data.timeline = section_data.timeline or {}
                    table.insert(results_summary, "Timeline Events: " .. #final_book_data.timeline)
                end
            end
            UIManager:scheduleIn(5, function() fetchNext(index + 1) end)
        end
        fetchNext(1)
    end)
end

function XRayPlugin:fetchAuthorInfo()
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    local props = self.ui.document:getProps() or {}
    local title, author = props.title or "Unknown", props.authors or "Unknown"
    local wait_msg = ButtonDialog:new{ title = self.loc:t("fetching_author", self.ai_provider or "AI"), text = title .. " - " .. author .. "\n\n" .. self.loc:t("fetching_wait"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(wait_msg) end }}} }
    UIManager:show(wait_msg)
    UIManager:scheduleIn(0.5, function()
        local author_data, error_code, error_msg = self.ai_helper:getAuthorData(title, author, self.ai_provider)
        UIManager:close(wait_msg)
        if not author_data then
            local error_dialog
            error_dialog = ButtonDialog:new{ title = "Error: Author Fetch", text = (error_msg or "Failed to fetch author info.") .. "\n\n(See crash.log in root for details)", buttons = {{{ text = self.loc:t("ok"), callback = function() UIManager:close(error_dialog) end }}} }
            UIManager:show(error_dialog)
            return
        end
        self.author_info = { name = author_data.author or author, description = author_data.author_bio or "No biography available.", birthDate = author_data.author_birth or "---", deathDate = author_data.author_death or "---" }
        if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
        local cache = self.cache_manager:loadCache(self.ui.document.file) or {}
        cache.author = self.author_info.name; cache.author_bio = self.author_info.description; cache.author_birth = self.author_info.birthDate; cache.author_death = self.author_info.deathDate
        self.cache_manager:saveCache(self.ui.document.file, cache)
        self:showAuthorInfo()
    end)
end

function XRayPlugin:showLocations()
    if not self.locations or #self.locations == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 }); return end
    local items = {}
    for _, loc in ipairs(self.locations) do table.insert(items, { text = (loc.name or "???"), callback = function() UIManager:show(InfoMessage:new{ text = (loc.name or "") .. "\n\n" .. (loc.description or "") .. "\n\nImportance: " .. (loc.importance or ""), timeout = 10 }) end }) end
    UIManager:show(Menu:new{ title = self.loc:t("menu_locations"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == "No biography available." then
        local ButtonDialog = require("ui/widget/buttondialog")
        local ask_dialog
        ask_dialog = ButtonDialog:new{ title = self.loc:t("menu_fetch_author") or "Fetch Author Info", text = self.loc:t("no_author_data_fetch"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(ask_dialog) end }, { text = self.loc:t("fetch_button") or "Fetch", is_enter_default = true, callback = function() UIManager:close(ask_dialog); UIManager:nextTick(function() self:fetchAuthorInfo() end) end }}} }
        UIManager:show(ask_dialog); return
    end
    local lines = { "NAME: " .. (self.author_info.name or "Unknown"), "BORN: " .. (self.author_info.birthDate or "---"), "DIED: " .. (self.author_info.deathDate or "---"), "", "BIOGRAPHY:", (self.author_info.description or "No biography available.") }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 15, width = Screen:getWidth() * 0.9 })
end

function XRayPlugin:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    UIManager:show(InfoMessage:new{ text = (meta.fullname or "X-Ray") .. " v" .. (meta.version or "?.?.?") .. "\n\n" .. (meta.description or ""), timeout = 15 })
end

function XRayPlugin:clearCache()
    if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}; self.locations = {}; self.timeline = {}; self.historical_figures = {}; self.author_info = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function XRayPlugin:toggleXRayMode()
    self.xray_mode_enabled = not self.xray_mode_enabled
    UIManager:show(InfoMessage:new{ text = self.loc:t("menu_xray_mode") .. " " .. (self.xray_mode_enabled and self.loc:t("xray_mode_active") or self.loc:t("xray_mode_inactive")), timeout = 3 })
end

function XRayPlugin:showTimeline()
    if not self.timeline or #self.timeline == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 }); return end
    local items = {}
    for _, ev in ipairs(self.timeline) do table.insert(items, { text = (ev.chapter or "") .. ": " .. (ev.event or ""), callback = function() UIManager:show(InfoMessage:new{ text = (ev.event or "") .. "\n\nImportance: " .. (ev.importance or ""), timeout = 10 }) end }) end
    UIManager:show(Menu:new{ title = self.loc:t("menu_timeline"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showHistoricalFigures()
    if not self.historical_figures or #self.historical_figures == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 }); return end
    local items = {}
    for _, fig in ipairs(self.historical_figures) do table.insert(items, { text = (fig.name or "???"), callback = function() UIManager:show(InfoMessage:new{ text = (fig.name or "") .. "\n\n" .. (fig.biography or ""), timeout = 15 }) end }) end
    UIManager:show(Menu:new{ title = self.loc:t("menu_historical_figures"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showChapterCharacters()
    if not self.chapter_analyzer then self.chapter_analyzer = require("chapteranalyzer"):new() end
    local text, title = self.chapter_analyzer:getCurrentChapterText(self.ui)
    if text then
        local found = self.chapter_analyzer:findCharactersInText(text, self.characters)
        if #found == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_characters_in_chapter") or "No characters found in this chapter.", timeout = 3 }); return end
        local items = {}
        for _, entry in ipairs(found) do table.insert(items, { text = string.format("%s (%d %s)\n   %s", entry.character.name or "Unknown", entry.count, self.loc:t("mentions") or "mentions", entry.character.role or ""), callback = function() self:showCharacterDetails(entry.character) end }) end
        UIManager:show(Menu:new{ title = (title or self.loc:t("menu_chapter_characters")) .. " (" .. #found .. ")", item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
    else UIManager:show(InfoMessage:new{ text = self.loc:t("chapter_text_error"), timeout = 3 }) end
end

function XRayPlugin:showQuickXRayMenu() self:showFullXRayMenu() end
function XRayPlugin:showFullXRayMenu()
    local menu_items = {}; self:addToMainMenu(menu_items)
    if menu_items.xray then UIManager:show(Menu:new{ title = self.loc:t("menu_xray") or "X-Ray", item_table = menu_items.xray.sub_item_table, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() }) end
end

function XRayPlugin:setGeminiAPIKey()
    local InputDialog = require("ui/widget/inputdialog")
    if not self.ai_helper then require("aihelper"):init(self.path) end
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("gemini_key_title"), input = self.ai_helper.providers.gemini.api_key or "", input_hint = self.loc:t("gemini_key_hint"), description = self.loc:t("gemini_key_desc"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("save"), is_enter_default = true, callback = function() local api_key = input_dialog:getInputText(); if api_key and #api_key > 0 then self.ai_helper:setAPIKey("gemini", api_key); self.ai_provider = "gemini"; UIManager:show(InfoMessage:new{ text = self.loc:t("gemini_key_saved"), timeout = 3 }) end; UIManager:close(input_dialog) end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function XRayPlugin:setChatGPTAPIKey()
    local InputDialog = require("ui/widget/inputdialog")
    if not self.ai_helper then require("aihelper"):init(self.path) end
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("chatgpt_key_title"), input = self.ai_helper.providers.chatgpt.api_key or "", input_hint = self.loc:t("chatgpt_key_hint"), description = self.loc:t("chatgpt_key_desc"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("save"), is_enter_default = true, callback = function() local api_key = input_dialog:getInputText(); if api_key and #api_key > 0 then self.ai_helper:setAPIKey("chatgpt", api_key); self.ai_provider = "chatgpt"; UIManager:show(InfoMessage:new{ text = self.loc:t("chatgpt_key_saved"), timeout = 3 }) end; UIManager:close(input_dialog) end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function XRayPlugin:selectAIProvider()
    if not self.ai_helper then require("aihelper"):init(self.path) end
    local provider_menu
    local providers = {}
    local function add(p, n)
        local key = self.ai_helper.providers[p] and self.ai_helper.providers[p].api_key
        if key and key ~= "" then table.insert(providers, { text = "[OK] " .. n .. " (" .. (self.ai_provider == p and "ACTIVE" or "INACTIVE") .. ")", callback = function() self.ai_provider = p; self.ai_helper:setDefaultProvider(p); UIManager:show(InfoMessage:new{ text = self.loc:t(p .. "_selected"), timeout = 2 }); if provider_menu then UIManager:close(provider_menu) end end })
        else table.insert(providers, { text = n .. " (No API key)", callback = function() UIManager:show(InfoMessage:new{ text = self.loc:t("set_key_first"), timeout = 3 }) end }) end
    end
    add("gemini", "Google Gemini"); add("chatgpt", "ChatGPT")
    provider_menu = Menu:new{ title = self.loc:t("provider_select_title"), item_table = providers, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() }
    UIManager:show(provider_menu)
end

function XRayPlugin:findCharacterByName(word)
    if not self.characters or not word then return nil end
    local word_lower = string.lower(word)
    for _, char in ipairs(self.characters) do local name_lower = string.lower(char.name or ""); if name_lower == word_lower or string.find(name_lower, word_lower, 1, true) then return char end end
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
    local text = "--- Current Configuration ---\n\nDefault Provider: " .. (self.ai_provider or "gemini") .. "\n\n"
    local function add(p, n)
        local c = self.ai_helper.providers[p]
        text = text .. n .. ":\n  Model: " .. (c.model or "???") .. "\n  Key Status: " .. (c.api_key and "SET" or "NOT SET") .. "\n" .. (c.ui_key_active and "  (Using UI Override Key)\n" or "  (Using Key from config.lua)\n") .. "\n"
    end
    add("gemini", "Google Gemini"); add("chatgpt", "ChatGPT")
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
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

return XRayPlugin
