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
    -- Register to main menu
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    -- Load localization module
    local Localization = require("localization_xray")
    self.loc = Localization
    self.loc:init(self.path) -- Load saved language preference with plugin path
    
    -- Initialize AI Helper
    local AIHelper = require("aihelper")
    self.ai_helper = AIHelper
    self.ai_helper:init(self.path)
    self.ai_provider = self.ai_helper.default_provider or "gemini"
    
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

function XRayPlugin:onReaderReady()
    -- Auto-load cache when book is opened
    self:autoLoadCache()
end

function XRayPlugin:onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    
    -- X-Ray Quick Menu action
    Dispatcher:registerAction("xray_quick_menu", {
        category = "none",
        event = "ShowXRayQuickMenu",
        title = self.loc:t("quick_menu_title") or "X-Ray Quick Menu",
        general = true,
        separator = true,
    })
    
    -- X-Ray Characters action
    Dispatcher:registerAction("xray_characters", {
        category = "none",
        event = "ShowXRayCharacters",
        title = self.loc:t("menu_characters") or "Characters",
        general = true,
    })
    
    -- X-Ray Chapter Characters action
    Dispatcher:registerAction("xray_chapter_characters", {
        category = "none",
        event = "ShowXRayChapterCharacters",
        title = self.loc:t("menu_chapter_characters") or "Chapter Characters",
        general = true,
    })
end

-- Event handlers for Dispatcher actions
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
    local cached_data = self.cache_manager:loadCache(book_path)
    
    if cached_data then
        self.book_data = cached_data
        self.characters = cached_data.characters or {}
        self.locations = cached_data.locations or {}
        self.themes = cached_data.themes or {}
        self.summary = cached_data.summary
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
        
        if #self.characters > 0 then
            self.xray_mode_enabled = true
            logger.info("XRayPlugin: X-Ray mode auto-enabled (silent)")
        end
        
        logger.info("XRayPlugin: Cache loaded successfully for", book_path)
    else
        logger.info("XRayPlugin: No cache found for auto-load")
    end
end

function XRayPlugin:getMenuCounts()
    return {
        characters = self.characters and #self.characters or 0,
        locations = self.locations and #self.locations or 0,
        themes = self.themes and #self.themes or 0,
        timeline = self.timeline and #self.timeline or 0,
        historical_figures = self.historical_figures and #self.historical_figures or 0,
    }
end

-- tricky hack: make our menu be the first under tools menu
local reader_menu_order = require("ui/elements/reader_menu_order")
if reader_menu_order and reader_menu_order.tools then
    -- Check if it's already there to avoid duplicate entries on reloads
    local found = false
    for _, v in ipairs(reader_menu_order.tools) do
        if v == "xray" then found = true; break end
    end
    if not found then
        table.insert(reader_menu_order.tools, 1, "xray")
    end
end

function XRayPlugin:addToMainMenu(menu_items)
    logger.info("XRayPlugin: addToMainMenu called")
    
    local counts = self:getMenuCounts()
    local gemini_model = self.ai_helper.providers.gemini.model or "???"
    local chatgpt_model = self.ai_helper.providers.chatgpt.model or "???"
    
    menu_items.xray = {
        text = self.loc:t("menu_xray") or "X-Ray",
        sorting_hint = "tools",
        callback = function()
            self:showQuickXRayMenu()
        end,
        hold_callback = function()
            self:showFullXRayMenu()
        end,
        sub_item_table = {
            {
                text = self.loc:t("menu_characters") .. (counts.characters > 0 and " (" .. counts.characters .. ")" or ""),
                keep_menu_open = true,
                callback = function()
                    self:showCharacters()
                end,
            },
            {
                text = self.loc:t("menu_chapter_characters"),
                keep_menu_open = true,
                callback = function()
                    self:showChapterCharacters()
                end,
            },
            {
                text = self.loc:t("menu_timeline") .. (counts.timeline > 0 and " (" .. counts.timeline .. " " .. self.loc:t("events") .. ")" or ""),
                keep_menu_open = true,
                callback = function()
                    self:showTimeline()
                end,
            },
            {
                text = self.loc:t("menu_historical_figures") .. (counts.historical_figures > 0 and " (" .. counts.historical_figures .. ")" or ""),
                keep_menu_open = true,
                callback = function()
                    self:showHistoricalFigures()
                end,
            },
            {
                text = self.loc:t("menu_locations") .. (counts.locations > 0 and " (" .. counts.locations .. ")" or ""),
                keep_menu_open = true,
                callback = function()
                    self:showLocations()
                end,
            },
            {
                text = self.loc:t("menu_author_info"),
                keep_menu_open = true,
                callback = function()
                    self:showAuthorInfo()
                end,
                separator = true,
            },
            {
                text = self.loc:t("menu_fetch_xray") or "Fetch X-Ray Data",
                keep_menu_open = true,
                callback = function()
                    self:fetchFromAI()
                end,
            },
            {
                text = self.loc:t("menu_fetch_author") or "Fetch Author Info (AI)",
                keep_menu_open = true,
                callback = function()
                    self:fetchAuthorInfo()
                end,
                separator = true,
            },
            {
                text = self.loc:t("menu_ai_settings"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_provider_select") .. " (" .. (self.ai_provider or "gemini") .. ")", 
                        keep_menu_open = true,
                        callback = function()
                            self:selectAIProvider()
                        end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_gemini_key") .. " (" .. (self.ai_helper.providers.gemini.api_key and "SET" or "NOT SET") .. ")", 
                        keep_menu_open = true,
                        callback = function()
                            self:setGeminiAPIKey()
                        end,
                    },
                    {
                        text = self.loc:t("menu_gemini_model") .. " (" .. gemini_model .. ")", 
                        keep_menu_open = true,
                        callback = function()
                            self:selectGeminiModel()
                        end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_chatgpt_key") .. " (" .. (self.ai_helper.providers.chatgpt.api_key and "SET" or "NOT SET") .. ")", 
                        keep_menu_open = true,
                        callback = function()
                            self:setChatGPTAPIKey()
                        end,
                    },
                    {
                        text = "ChatGPT Model (" .. chatgpt_model .. ")", 
                        keep_menu_open = true,
                        callback = function()
                            self:selectChatGPTModel()
                        end,
                        separator = true,
                    },
                    {
                        text = "View All Config Values", 
                        keep_menu_open = true,
                        callback = function()
                            self:showConfigSummary()
                        end,
                    },
                }
            },
            {
                text = self.loc:t("menu_clear_cache"),
                keep_menu_open = true,
                callback = function()
                    self:clearCache()
                end,
                separator = true,
            },
            {
                text = self.loc:t("menu_xray_mode") .. " " .. (self.xray_mode_enabled and self.loc:t("xray_mode_active") or self.loc:t("xray_mode_inactive")),
                keep_menu_open = true,
                callback = function()
                    self:toggleXRayMode()
                end,
            },
            {
                text = self.loc:t("menu_language"),
                keep_menu_open = true,
                callback = function()
                    self:showLanguageSelection()
                end,
                separator = true,
            },
            {
                text = self.loc:t("menu_about"),
                keep_menu_open = true,
                callback = function()
                    self:showAbout()
                end,
            },
        }
    }
end

function XRayPlugin:showLanguageSelection()
    local ButtonDialog = require("ui/widget/buttondialog")
    local current_lang = self.loc:getLanguage()
    
    local function changeLang(lang_code)
        UIManager:close(self.ldlg)
        self.loc:setLanguage(lang_code)
        UIManager:show(InfoMessage:new{
            text = "[OK] " .. self.loc:t("language_changed") .. "\n\n" .. self.loc:t("please_restart"),
            timeout = 4 
        })
    end
    
    local buttons = {
        {{ text = "English" .. (current_lang == "en" and " [OK]" or ""), callback = function() changeLang("en") end }},
        {{ text = "Türkçe" .. (current_lang == "tr" and " [OK]" or ""), callback = function() changeLang("tr") end }},
        {{ text = "Português" .. (current_lang == "pt_br" and " [OK]" or ""), callback = function() changeLang("pt_br") end }},
        {{ text = "Español" .. (current_lang == "es" and " [OK]" or ""), callback = function() changeLang("es") end }},
    }
    
    self.ldlg = ButtonDialog:new{title = "Language Selection", buttons = buttons}
    UIManager:show(self.ldlg)
end

function XRayPlugin:showCharacters()
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 })
        return
    end
    
    local items = {
        { 
            text = "[Search] " .. self.loc:t("search_character"), 
            callback = function() self:showCharacterSearch() end 
        }
    }
    
    for _, char in ipairs(self.characters) do
        local name = char.name or "Unknown"
        -- Bold the name in the menu
        local text = "• " .. name
        if char.description and #char.description > 0 then
            text = text .. "\n  " .. char.description:sub(1, 80) .. ( #char.description > 80 and "..." or "")
        end
        table.insert(items, {
            text = text,
            callback = function() self:showCharacterDetails(char) end
        })
    end
    
    UIManager:show(Menu:new{
        title = self.loc:t("menu_characters") .. " (" .. #self.characters .. ")",
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    })
end

function XRayPlugin:showCharacterDetails(character)
    local lines = {
        "NAME: " .. (character.name or "???"),
        "ROLE: " .. (character.role or "---"),
        "GENDER: " .. (character.gender or "---"),
        "OCCUPATION: " .. (character.occupation or "---"),
        "",
        "DESCRIPTION:",
        character.description or "---"
    }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), width = Screen:getWidth() * 0.9 })
end

function XRayPlugin:selectGeminiModel()
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end

    local current_model = self.ai_helper.providers.gemini.model or "gemini-2.5-flash"
    local ButtonDialog = require("ui/widget/buttondialog")
    local buttons = {
        {{ text = "Gemini 2.5 Flash" .. (current_model == "gemini-2.5-flash" and " [OK]" or ""), 
           callback = function() self.ai_helper:setGeminiModel("gemini-2.5-flash"); UIManager:close(self.dlg) end }},
        {{ text = "Gemini 2.5 Pro" .. (current_model == "gemini-2.5-pro" and " [OK]" or ""), 
           callback = function() self.ai_helper:setGeminiModel("gemini-2.5-pro"); UIManager:close(self.dlg) end }},
        {{ text = "Gemini 3 Pro Preview" .. (current_model == "gemini-3-pro-preview" and " [OK]" or ""), 
           callback = function() self.ai_helper:setGeminiModel("gemini-3-pro-preview"); UIManager:close(self.dlg) end }},
        {{ text = "Manual Input...", 
           callback = function() 
               UIManager:close(self.dlg)
               local InputDialog = require("ui/widget/inputdialog")
               local manual_dialog
               manual_dialog = InputDialog:new{
                   title = "Gemini Model Manual Input",
                   input = current_model,
                   buttons = {
                       {{ text = self.loc:t("cancel"), callback = function() UIManager:close(manual_dialog) end }},
                       {{ text = self.loc:t("save"), is_enter_default = true, callback = function()
                           local model = manual_dialog:getInputText()
                           if model and #model > 0 then
                               self.ai_helper:setGeminiModel(model)
                               UIManager:show(InfoMessage:new{ text = "Model set: " .. model, timeout = 2 })
                           end
                           UIManager:close(manual_dialog)
                       end }},
                   }
               }
               UIManager:show(manual_dialog)
               manual_dialog:onShowKeyboard()
           end }},
    }
    self.dlg = ButtonDialog:new{ title = self.loc:t("gemini_model_title"), buttons = buttons }
    UIManager:show(self.dlg)
end

function XRayPlugin:fetchFromAI()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        self:askSpoilerPreference()
    end)
end

function XRayPlugin:askSpoilerPreference()
    local current_page = self.ui:getCurrentPage()
    local total_pages = self.ui.document:getPageCount()
    local reading_percent = math.floor((current_page / total_pages) * 100)
    
    local spoiler_menu = Menu:new{
        title = self.loc:t("spoiler_preference_title"),
        item_table = {
            { text = self.loc:t("spoiler_free_option", reading_percent),
              callback = function() UIManager:close(spoiler_menu); self:continueWithFetch(reading_percent) end },
            { text = self.loc:t("full_book_option"),
              callback = function() UIManager:close(spoiler_menu); self:continueWithFetch(100) end },
            { text = self.loc:t("cancel"), callback = function() UIManager:close(spoiler_menu) end },
        },
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
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
    local current_page = self.ui:getCurrentPage()
    local props = self.ui.document:getProps() or {}
    local title = props.title or "Unknown"
    local author = props.authors or "Unknown"
    local series = props.series or props.Series
    local series_index = props.series_index or props.SeriesIndex
    
    -- Show a persistent ButtonDialog instead of InfoMessage
    local wait_msg
    local is_cancelled = false
    wait_msg = ButtonDialog:new{ 
        title = self.loc:t("fetching_ai", self.ai_provider or "AI"),
        text = title .. "\n\n" .. self.loc:t("fetching_wait") .. "\n\n" .. (self.loc:t("dont_touch") or "Do not touch the screen."), 
        buttons = {
            {{ text = self.loc:t("cancel"), id = "close", callback = function() 
                is_cancelled = true
                UIManager:close(wait_msg) 
            end }}
        },
        close_on_touch_outside = false,
    }
    UIManager:show(wait_msg)
    
    -- Use a 0.5-second delay to ENSURE the Dialog renders before the blocking work starts
    UIManager:scheduleIn(0.5, function()
        -- CRITICAL: Check if user already cancelled during the 0.5s window
        if is_cancelled then return end

        if not self.chapter_analyzer then 
            self.chapter_analyzer = require("chapteranalyzer"):new() 
        end
        
        -- Step 1: Extract book text and chapter samples
        -- Pass current_page to optimize extraction (avoids slow pagination)
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 100000, function(progress)
            logger.info("XRayPlugin: Extraction progress:", math.floor(progress * 100), "%")
        end, current_page)
        
        local chapter_samples = self.chapter_analyzer:getDetailedChapterSamples(self.ui)
        
        if (not book_text or #book_text < 10) and not chapter_samples then
            if wait_msg then UIManager:close(wait_msg) end
            UIManager:show(InfoMessage:new{ text = "Error: Could not extract book text.", timeout = 5 })
            return
        end

        local annotations = self.chapter_analyzer:getAnnotationsForAnalysis(self.ui)
        logger.info("XRayPlugin: Sending context to AI. Text length:", #book_text or 0, "Chapter samples:", chapter_samples and #chapter_samples or 0)
        
        local filename = self.ui.document.file:match("([^/\\]+)$")
        local context = { 
            reading_percent = reading_percent, 
            spoiler_free = reading_percent < 100,
            filename = filename,
            series = series,
            series_index = series_index,
            book_text = book_text,
            chapter_samples = chapter_samples,
            annotations = annotations
        }
        
        -- Step 2: Make the AI request (using non-blocking Trapper subprocess)
        self.ai_helper:setTrapWidget(wait_msg)
        local book_data, error_code, error_msg = self.ai_helper:getBookData(title, author, self.ai_provider or "gemini", context)
        
        -- Step 3: Cleanup
        self.ai_helper:resetTrapWidget()
        if wait_msg then UIManager:close(wait_msg) end
        
        if error_code == "USER_CANCELLED" then
            logger.info("XRayPlugin: AI Fetch cancelled by user")
            return
        end
        
        if not book_data then
            -- Check for subprocess error
            if error_code == "error_subprocess" then
                UIManager:show(InfoMessage:new{
                    text = "AI Subprocess Error: Please check logs.",
                    timeout = 99999999, -- Effectively permanent until replaced
                })
            else
                UIManager:show(InfoMessage:new{
                    text = (error_msg or "AI Fetch Failed"),
                    timeout = 99999999, -- Effectively permanent until replaced
                })
            end
            return
        end
        
        -- Process results
        self.characters = book_data.characters or {}
        self.locations = book_data.locations or {}
        self.themes = book_data.themes or {}
        self.summary = book_data.summary
        self.timeline = book_data.timeline or {}
        self.historical_figures = book_data.historical_figures or {}
        
        if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
        local cache_saved = self.cache_manager:saveCache(self.ui.document.file, book_data)
        
        local provider_name = self.ai_provider or "AI" -- Fallback to AI if provider name is not set
        local summary_text = self.summary or "No summary provided by AI."
        if summary_text == "" then summary_text = "No summary provided by AI." end
        
        local success_message = self.loc:t(
            "ai_fetch_complete",
            provider_name,                       -- 1. %s
            book_data.book_title or title,      -- 2. %s
            book_data.author or author,         -- 3. %s
            #self.characters,                    -- 4. %d
            #self.locations,                     -- 5. %d
            #self.themes,                        -- 6. %d
            #self.timeline,                      -- 7. %d
            #self.historical_figures,            -- 8. %d
            cache_saved and self.loc:t("cache_saved") or self.loc:t("cache_save_failed"), -- 9. %s
            summary_text                         -- 10. %s
        )
        
        -- Show success dialog with summary
        local success_dialog
        success_dialog = ButtonDialog:new{
            title = self.loc:t("fetch_successful") or "Fetch successful",
            text = success_message,
            buttons = {
                {
                    {
                        text = self.loc:t("ok"),
                        callback = function() UIManager:close(success_dialog) end,
                    }
                }
            }
        }
        UIManager:show(success_dialog)
    end)
end

function XRayPlugin:fetchAuthorInfo()
    local ButtonDialog = require("ui/widget/buttondialog")
    local props = self.ui.document:getProps() or {}
    local title = props.title or "Unknown"
    local author = props.authors or "Unknown"
    
    local wait_msg = ButtonDialog:new{
        title = self.loc:t("fetching_author", self.ai_provider or "AI"),
        text = title .. " - " .. author .. "\n\n" .. self.loc:t("fetching_wait"),
        buttons = {
            {{ text = self.loc:t("cancel"), callback = function() UIManager:close(wait_msg) end }}
        }
    }
    UIManager:show(wait_msg)
    
    UIManager:scheduleIn(0.5, function()
        local author_data, error_code, error_msg = self.ai_helper:getAuthorData(title, author, self.ai_provider)
        UIManager:close(wait_msg)
        
        if not author_data then
            UIManager:show(InfoMessage:new{ text = error_msg or "Failed to fetch author info.", timeout = 5 })
            return
        end
        
        self.author_info = {
            name = author_data.author or author,
            description = author_data.author_bio or "No biography available.",
            birthDate = author_data.author_birth or "---",
            deathDate = author_data.author_death or "---"
        }
        
        -- Merge with existing cache if possible
        if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
        local existing_cache = self.cache_manager:loadCache(self.ui.document.file) or {}
        existing_cache.author = self.author_info.name
        existing_cache.author_bio = self.author_info.description
        existing_cache.author_birth = self.author_info.birthDate
        existing_cache.author_death = self.author_info.deathDate
        
        self.cache_manager:saveCache(self.ui.document.file, existing_cache)
        
        self:showAuthorInfo()
    end)
end

function XRayPlugin:showLocations()
    if not self.locations or #self.locations == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return
    end
    local items = {}
    for _, loc in ipairs(self.locations) do
        table.insert(items, { text = (loc.name or "???"), callback = function() 
            UIManager:show(InfoMessage:new{ text = (loc.name or "") .. "\n\n" .. (loc.description or "") .. "\n\nImportance: " .. (loc.importance or ""), timeout = 10 })
        end })
    end
    UIManager:show(Menu:new{ title = self.loc:t("menu_locations"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == "No biography available." then
        UIManager:show(ConfirmBox:new{
            text = self.loc:t("no_author_data_fetch"),
            ok_text = self.loc:t("fetch_button") or "Fetch",
            cancel_text = self.loc:t("cancel"),
            callback = function()
                self:fetchAuthorInfo()
            end
        })
        return
    end
    
    local lines = {
        "NAME: " .. (self.author_info.name or "Unknown"),
        "BORN: " .. (self.author_info.birthDate or self.author_info.birth or "---"),
        "DIED: " .. (self.author_info.deathDate or self.author_info.death or "---"),
        "",
        "BIOGRAPHY:",
        (self.author_info.description or self.author_info.bio or "No biography available.")
    }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 15, width = Screen:getWidth() * 0.9 })
end

function XRayPlugin:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    local text = (meta.fullname or "X-Ray") .. " v" .. (meta.version or "?.?.?") .. "\n\n" .. (meta.description or "")
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end

function XRayPlugin:clearCache()
    if not self.cache_manager then self.cache_manager = require("cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}
    self.locations = {}
    self.themes = {}
    self.summary = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function XRayPlugin:toggleXRayMode()
    self.xray_mode_enabled = not self.xray_mode_enabled
    local status = self.xray_mode_enabled and self.loc:t("xray_mode_active") or self.loc:t("xray_mode_inactive")
    UIManager:show(InfoMessage:new{ text = self.loc:t("menu_xray_mode") .. " " .. status, timeout = 3 })
end

function XRayPlugin:showTimeline()
    if not self.timeline or #self.timeline == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 })
        return
    end
    local items = {}
    for _, ev in ipairs(self.timeline) do
        table.insert(items, { text = (ev.chapter or "") .. ": " .. (ev.event or ""), callback = function()
            UIManager:show(InfoMessage:new{ text = (ev.event or "") .. "\n\nImportance: " .. (ev.importance or ""), timeout = 10 })
        end })
    end
    UIManager:show(Menu:new{ title = self.loc:t("menu_timeline"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showHistoricalFigures()
    if not self.historical_figures or #self.historical_figures == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 })
        return
    end
    local items = {}
    for _, fig in ipairs(self.historical_figures) do
        table.insert(items, { text = (fig.name or "???"), callback = function()
            UIManager:show(InfoMessage:new{ text = (fig.name or "") .. "\n\n" .. (fig.biography or ""), timeout = 15 })
        end })
    end
    UIManager:show(Menu:new{ title = self.loc:t("menu_historical_figures"), item_table = items, is_borderless = true, width = Screen:getWidth(), height = Screen:getHeight() })
end

function XRayPlugin:showSummary()
    UIManager:show(InfoMessage:new{ text = self.summary or self.loc:t("no_summary_data"), timeout = 15 })
end

function XRayPlugin:showThemes()
    if not self.themes or #self.themes == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_theme_data"), timeout = 3 })
        return
    end
    local text = table.concat(self.themes, "\n• ")
    UIManager:show(InfoMessage:new{ text = "(theme) " .. self.loc:t("themes_title") .. ":\n\n• " .. text, timeout = 15 })
end

function XRayPlugin:showChapterCharacters()
    if not self.chapter_analyzer then self.chapter_analyzer = require("chapteranalyzer"):new() end
    local text, title = self.chapter_analyzer:getCurrentChapterText(self.ui)
    
    if text then
        local found = self.chapter_analyzer:findCharactersInText(text, self.characters)
        
        if #found == 0 then
            UIManager:show(InfoMessage:new{ text = self.loc:t("no_characters_in_chapter") or "No characters found in this chapter.", timeout = 3 })
            return
        end
        
        local items = {}
        for _, entry in ipairs(found) do
            local char = entry.character
            local count = entry.count
            local name = char.name or "Unknown"
            
            table.insert(items, {
                text = string.format("%s (%d %s)\n   %s", 
                    name, 
                    count, 
                    self.loc:t("mentions") or "mentions",
                    char.role or ""),
                callback = function()
                    self:showCharacterDetails(char)
                end
            })
        end
        
        UIManager:show(Menu:new{
            title = (title or self.loc:t("menu_chapter_characters")) .. " (" .. #found .. ")",
            item_table = items,
            is_borderless = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
        })
    else
        UIManager:show(InfoMessage:new{ text = self.loc:t("chapter_text_error"), timeout = 3 })
    end
end

function XRayPlugin:showQuickXRayMenu()
    self:showFullXRayMenu()
end

function XRayPlugin:showFullXRayMenu()
    local menu_items = {}
    self:addToMainMenu(menu_items)
    if menu_items.xray then
        UIManager:show(Menu:new{
            title = self.loc:t("menu_xray") or "X-Ray",
            item_table = menu_items.xray.sub_item_table,
            is_borderless = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
        })
    end
end

function XRayPlugin:setGeminiAPIKey()
    local InputDialog = require("ui/widget/inputdialog")
    
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    
    local current_key = self.ai_helper.providers.gemini.api_key or ""
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = self.loc:t("gemini_key_title"), 
        input = current_key,
        input_hint = self.loc:t("gemini_key_hint"), 
        description = self.loc:t("gemini_key_desc"), 
        buttons = {
            {
                {
                    text = self.loc:t("cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = self.loc:t("save"),
                    is_enter_default = true,
                    callback = function()
                        local api_key = input_dialog:getInputText()
                        if api_key and #api_key > 0 then
                            self.ai_helper:setAPIKey("gemini", api_key)
                            self.ai_provider = "gemini"
                            
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("gemini_key_saved"), 
                                timeout = 3,
                            })                            
                        end
                        UIManager:close(input_dialog)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function XRayPlugin:setChatGPTAPIKey()
    local InputDialog = require("ui/widget/inputdialog")
    
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    
    local current_key = self.ai_helper.providers.chatgpt.api_key or ""
    
    local input_dialog
    input_dialog = InputDialog:new{
        title = self.loc:t("chatgpt_key_title"), 
        input = current_key,
        input_hint = self.loc:t("chatgpt_key_hint"), 
        description = self.loc:t("chatgpt_key_desc"), 
        buttons = {
            {
                {
                    text = self.loc:t("cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = self.loc:t("save"),
                    is_enter_default = true,
                    callback = function()
                        local api_key = input_dialog:getInputText()
                        if api_key and #api_key > 0 then
                            self.ai_helper:setAPIKey("chatgpt", api_key)
                            self.ai_provider = "chatgpt"
                            
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("chatgpt_key_saved"), 
                                timeout = 3,
                            })
                        end
                        UIManager:close(input_dialog)
                    end,
                },
            }
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function XRayPlugin:selectAIProvider()
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    
    if not self.ai_provider and self.ai_helper.default_provider then
        self.ai_provider = self.ai_helper.default_provider
    end
    
    local provider_menu 

    local providers = {}
    
    local gemini_key = self.ai_helper.providers.gemini and self.ai_helper.providers.gemini.api_key
    if gemini_key and gemini_key ~= "" then
        table.insert(providers, {
            text = "[OK] Google Gemini (" .. (self.ai_provider == "gemini" and "ACTIVE" or "INACTIVE") .. ")",
            callback = function()
                self.ai_provider = "gemini"
                self.ai_helper:setDefaultProvider("gemini")
                UIManager:show(InfoMessage:new{
                    text = self.loc:t("gemini_selected"), 
                    timeout = 2,
                })
                if provider_menu then UIManager:close(provider_menu) end
            end,
        })
    else
        table.insert(providers, {
            text = "Google Gemini (No API key)",
            callback = function()
                UIManager:show(InfoMessage:new{ text = self.loc:t("set_key_first"), timeout = 3 })
            end,
        })
    end
    
    local chatgpt_key = self.ai_helper.providers.chatgpt and self.ai_helper.providers.chatgpt.api_key
    if chatgpt_key and chatgpt_key ~= "" then
        table.insert(providers, {
            text = "[OK] ChatGPT (" .. (self.ai_provider == "chatgpt" and "ACTIVE" or "INACTIVE") .. ")",
            callback = function()
                self.ai_provider = "chatgpt"
                self.ai_helper:setDefaultProvider("chatgpt")
                UIManager:show(InfoMessage:new{
                    text = self.loc:t("chatgpt_selected"), 
                    timeout = 2,
                })
                if provider_menu then UIManager:close(provider_menu) end
            end,
        })
    else
        table.insert(providers, {
            text = "ChatGPT (No API key)",
            callback = function()
                UIManager:show(InfoMessage:new{ text = self.loc:t("set_key_first"), timeout = 3 })
            end,
        })
    end
    
    provider_menu = Menu:new{
        title = self.loc:t("provider_select_title"), 
        item_table = providers,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    
    UIManager:show(provider_menu)
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
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 })
        return
    end
    
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = self.loc:t("search_character_title"),
        input = "",
        input_hint = self.loc:t("search_hint"),
        buttons = {
            {
                {
                    text = self.loc:t("cancel"),
                    callback = function() UIManager:close(input_dialog) end,
                },
                {
                    text = self.loc:t("search_button"),
                    is_enter_default = true,
                    callback = function()
                        local search_text = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if search_text and #search_text > 0 then
                            local found_char = self:findCharacterByName(search_text)
                            if found_char then
                                self:showCharacterDetails(found_char)
                            else
                                UIManager:show(InfoMessage:new{
                                    text = string.format(self.loc:t("character_not_found"), search_text),
                                    timeout = 3,
                                })
                            end
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function XRayPlugin:selectChatGPTModel()
    if not self.ai_helper then
        local AIHelper = require("aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end

    local current_model = self.ai_helper.providers.chatgpt.model or "gpt-4o-mini"
    local ButtonDialog = require("ui/widget/buttondialog")
    local buttons = {
        {{ text = "GPT-4o Mini" .. (current_model == "gpt-4o-mini" and " [OK]" or ""), 
           callback = function() self.ai_helper:setChatGPTModel("gpt-4o-mini"); UIManager:close(self.dlg) end }},
        {{ text = "GPT-4o" .. (current_model == "gpt-4o" and " [OK]" or ""), 
           callback = function() self.ai_helper:setChatGPTModel("gpt-4o"); UIManager:close(self.dlg) end }},
        {{ text = "Manual Input...", 
           callback = function() 
               UIManager:close(self.dlg)
               local InputDialog = require("ui/widget/inputdialog")
               local manual_dialog
               manual_dialog = InputDialog:new{
                   title = "ChatGPT Model Manual Input",
                   input = current_model,
                   buttons = {
                       {{ text = self.loc:t("cancel"), callback = function() UIManager:close(manual_dialog) end }},
                       {{ text = self.loc:t("save"), is_enter_default = true, callback = function()
                           local model = manual_dialog:getInputText()
                           if model and #model > 0 then
                               self.ai_helper:setChatGPTModel(model)
                               UIManager:show(InfoMessage:new{ text = "Model set: " .. model, timeout = 2 })
                           end
                           UIManager:close(manual_dialog)
                       end }},
                   }
               }
               UIManager:show(manual_dialog)
               manual_dialog:onShowKeyboard()
           end }},
    }
    self.dlg = ButtonDialog:new{ title = "Select ChatGPT Model", buttons = buttons }
    UIManager:show(self.dlg)
end

function XRayPlugin:showConfigSummary()
    local text = "--- Current Configuration ---\n\n"
    text = text .. "Default Provider: " .. (self.ai_provider or "gemini") .. "\n\n"
    
    local gemini = self.ai_helper.providers.gemini
    text = text .. "Google Gemini:\n"
    text = text .. "  Model: " .. (gemini.model or "???") .. "\n"
    text = text .. "  Key Status: " .. (gemini.api_key and "SET" or "NOT SET") .. "\n"
    if gemini.ui_key_active then
        text = text .. "  (Using UI Override Key)\n"
    else
        text = text .. "  (Using Key from config.lua)\n"
    end
    text = text .. "\n"
    
    local chatgpt = self.ai_helper.providers.chatgpt
    text = text .. "ChatGPT:\n"
    text = text .. "  Model: " .. (chatgpt.model or "???") .. "\n"
    text = text .. "  Key Status: " .. (chatgpt.api_key and "SET" or "NOT SET") .. "\n"
    if chatgpt.ui_key_active then
        text = text .. "  (Using UI Override Key)\n"
    else
        text = text .. "  (Using Key from config.lua)\n"
    end
    
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end

return XRayPlugin
