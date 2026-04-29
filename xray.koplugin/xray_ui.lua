-- X-Ray UI and Menu Functions

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local ButtonDialog = require("ui/widget/buttondialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local _ = require("gettext")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

function M:showLanguageSelection()
    local ButtonDialog = require("ui/widget/buttondialog")
    
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    
    local function changeLang(lang_code)
        UIManager:close(self.ldlg)
        self.ldlg = nil
        
        if self.ai_helper then
            self.ai_helper:saveSettings({ language = lang_code })
        end
        
        -- Apply the new setting immediately
        self:applyLanguageLogic()
        
        local msg = (self.loc and self.loc:t("language_changed_reopen")) or "Language changed. Reopen the menu to see the changes."
        
        -- Use the centralized silver-bullet clear
        self:closeAllMenus()
        
        UIManager:show(InfoMessage:new{
            text = "[OK] " .. msg,
            timeout = 3
        })
    end
    
    local buttons = {
        {
            { text = (self.loc:t("lang_follow_system") or "Automatic (Follow System)") .. (settings_lang == "auto" and " [OK]" or ""), callback = function() changeLang("auto") end },
            { text = (self.loc:t("lang_follow_book") or "Automatic (Follow Book)") .. (settings_lang == "book" and " [OK]" or ""), callback = function() changeLang("book") end },
        },
        {{ text = "English" .. (settings_lang == "en" and " [OK]" or ""), callback = function() changeLang("en") end }},
        {{ text = "Deutsch" .. (settings_lang == "de" and " [OK]" or ""), callback = function() changeLang("de") end }},
        {{ text = "Français" .. (settings_lang == "fr" and " [OK]" or ""), callback = function() changeLang("fr") end }},
        {{ text = "Русский" .. (settings_lang == "ru" and " [OK]" or ""), callback = function() changeLang("ru") end }},
        {{ text = "简体中文" .. (settings_lang == "zh_CN" and " [OK]" or ""), callback = function() changeLang("zh_CN") end }},
        {{ text = "Türkçe" .. (settings_lang == "tr" and " [OK]" or ""), callback = function() changeLang("tr") end }},
        {{ text = "Português" .. (settings_lang == "pt_br" and " [OK]" or ""), callback = function() changeLang("pt_br") end }},
        {{ text = "Español" .. (settings_lang == "es" and " [OK]" or ""), callback = function() changeLang("es") end }},
        {{ text = "Українська" .. (settings_lang == "uk" and " [OK]" or ""), callback = function() changeLang("uk") end }},
    }
    
    local dialog_title = (self.loc and self.loc:t("menu_language")) or "Language Selection"
    self.ldlg = ButtonDialog:new{title = dialog_title, buttons = buttons}
    UIManager:show(self.ldlg)
end

function M:resolveLanguage(code)
    local supported = { en=1, de=1, fr=1, ru=1, zh_CN=1, tr=1, pt_br=1, es=1, uk=1 }
    
    if code == "auto" or not code then
        local gettext = require("gettext")
        local ko_lang = gettext.getLanguage and gettext.getLanguage()
        
        -- Fallback to G_reader_settings if gettext doesn't provide it
        if not ko_lang and G_reader_settings then
            ko_lang = G_reader_settings:readSetting("language")
        end
        
        if ko_lang then
            local lang = ko_lang:sub(1, 2):lower()
            if ko_lang:lower():find("zh_cn") or ko_lang:lower():find("zh-cn") then lang = "zh_CN"
            elseif ko_lang:lower():find("pt_br") or ko_lang:lower():find("pt-br") then lang = "pt_br" end
            if supported[lang] then return lang end
        end
        return "en"
    elseif code == "book" then
        if self.ui and self.ui.document then
            local props = self.ui.document:getProps()
            local book_lang = props.language
            if book_lang then
                local lang = book_lang:sub(1, 2):lower()
                if book_lang:lower():find("zh") then lang = "zh_CN"
                elseif book_lang:lower():find("pt") then lang = "pt_br" end
                if supported[lang] then return lang end
            end
        end
        return self:resolveLanguage("auto")
    end
    return code or "en"
end

function M:applyLanguageLogic()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    local resolved = self:resolveLanguage(settings_lang)
    
    self:log("XRayPlugin: Applying language logic. Settings: " .. tostring(settings_lang) .. ", Resolved: " .. tostring(resolved))
    
    if self.loc and self.loc.setLanguage then
        self.loc:setLanguage(resolved)
    end
    
    if self.ai_helper then
        self.ai_helper.current_language = resolved
        self.ai_helper:loadLanguage()
    end
end

function M:checkBookLanguageMatch()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    -- Only suggest if we are NOT in "Follow Book" mode already
    if settings_lang == "book" then return end
    
    if not self.ui or not self.ui.document then return end
    local props = self.ui.document:getProps()
    local book_lang = props.language
    if not book_lang or book_lang == "" then return end
    
    local lang = book_lang:sub(1, 2):lower()
    if book_lang:find("zh") then lang = "zh_CN"
    elseif book_lang:find("pt") then lang = "pt_br" end
    
    local supported = {
        en = "English", de = "Deutsch", fr = "Français",
        ru = "Русский", zh_CN = "简体中文", tr = "Türkçe",
        pt_br = "Português", es = "Español", uk = "Українська"
    }
    
    if not supported[lang] then return end
    
    local current_lang = self.loc:getLanguage()
    if lang == current_lang then return end
    
    if self.suggestion_dismissed[self.ui.document.file] then return end
    
    -- Check if we should ignore this book (from cache)
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cache = self.cache_manager:loadCache(self.ui.document.file)
    if cache and cache.ignore_lang_mismatch then return end

    -- Show prompt
    local lang_name = supported[lang]
    local msg = string.format(self.loc:t("msg_suggest_lang") or "This book is in %s. Switch X-Ray language to match?", lang_name)
    
    local ButtonDialog = require("ui/widget/buttondialog")
    local mismatch_dialog
    mismatch_dialog = ButtonDialog:new{
        title = self.loc:t("lang_mismatch_title") or "Language Mismatch",
        text = msg,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        if self.ai_helper then
                            self.ai_helper:saveSettings({ language = lang })
                            self:applyLanguageLogic()
                            UIManager:close(mismatch_dialog)
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("language_changed_reopen") or "Language changed.",
                                timeout = 3
                            })
                        end
                    end
                },
                {
                    text = self.loc:t("no") or "No",
                    callback = function()
                        self.suggestion_dismissed[self.ui.document.file] = true
                        UIManager:close(mismatch_dialog)
                    end
                }
            },
            {
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        local current_cache = self.cache_manager:loadCache(self.ui.document.file) or {}
                        current_cache.ignore_lang_mismatch = true
                        self.cache_manager:saveCache(self.ui.document.file, current_cache)
                        UIManager:close(mismatch_dialog)
                    end
                }
            }
        }
    }
    UIManager:show(mismatch_dialog)
end

function M:closeAllMenus()
    -- Mark as cancelled to stop background tasks
    self.is_cancelled = true
    
    if self.bg_scan_handle and self.bg_scan_handle.cancel then
        pcall(function() self.bg_scan_handle:cancel() end)
    end
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        pcall(function() self.active_mention_scan.cancel_handle:cancel() end)
        self.active_mention_scan = nil
    end

    -- 1. Close all custom plugin modals instantly
    local menus = {
        self.mentions_menu, self.char_menu, self.loc_menu,
        self.timeline_menu, self.hf_menu, self.xray_menu,
        self.active_details_dialog
    }
    for i = 1, 7 do
        if menus[i] then pcall(function() UIManager:close(menus[i]) end) end
    end
    self.mentions_menu = nil; self.char_menu = nil; self.loc_menu = nil
    self.timeline_menu = nil; self.hf_menu = nil; self.xray_menu = nil
    self.active_details_dialog = nil
    
    local function executeClear()
        -- 2. Dismiss native KOReader top menu stack
        if self.ui and self.ui.menu then
            pcall(function()
                if type(self.ui.menu.onCloseReaderMenu) == "function" then
                    self.ui.menu:onCloseReaderMenu()
                end
            end)
        end

        -- 3. Cleanup selection and highlights
        pcall(function()
            local Event = require("ui/event")
            local ok, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
            if ok and DictQuickLookup and DictQuickLookup.window_list then
                for i = #DictQuickLookup.window_list, 1, -1 do
                    local window = DictQuickLookup.window_list[i]
                    if window and window.onClose then pcall(function() window:onClose() end) end
                end
            end
            if self.ui.highlight and self.ui.highlight.clear then
                pcall(function() self.ui.highlight:clear() end)
            end
            self.ui:handleEvent(Event:new("ClearSelection"))
        end)
    end
    
    -- Pass 1: Immediate
    executeClear()
    
    -- Pass 2: Staggered 100ms safety pass
    UIManager:scheduleIn(0.1, function()
        executeClear()
        -- Reset cancellation flag after all passes are done
        self.is_cancelled = false
    end)
end

function M:showCharacters()
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 })
        return
    end

    local items = {
        { text = "⌕ " .. self.loc:t("search_character"), callback = function() self:showCharacterSearch() end },
        { text = "✚ " .. (self.loc:t("menu_fetch_more_chars") or "Fetch More Characters"), keep_menu_open = true, callback = function() self:fetchMoreCharacters() end, separator = true },
    }
    for _, char in ipairs(self.characters) do
        local name = char.name or "Unknown"
        local text = "• " .. name
        if char.description and #char.description > 0 then text = text .. "\n  " .. char.description:sub(1, 80) .. (#char.description > 80 and "..." or "") end
        table.insert(items, { 
            text = text, 
            keep_menu_open = true,
            callback = function() self:showCharacterDetails(char) end 
        })
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
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.char_menu)
end

function M:findRelatedEntities(text, exclude_name)
    if not text or text == "" then return {} end
    local related = {}
    local seen = {}
    if exclude_name then seen[exclude_name:lower()] = true end

    local lower_text = text:lower()

    -- Honorifics: fast-path blocklist for known titles.
    -- Tokens < 3 chars are already blocked by isTooGeneric's length check;
    -- 3-char titles (mr., mrs, sir, dr., etc.) are listed here since they can
    -- have plausible frequency ratios in densely character-focused descriptions.
    local honorifics = {
        ["mr."] = true, ["mrs"] = true, ["ms."] = true, ["sir"] = true,
        ["dr."] = true, ["rev"] = true, ["rev."] = true, ["lt."] = true,
        ["col"] = true, ["col."] = true, ["sgt"] = true, ["sgt."] = true,
        ["gen"] = true, ["gen."] = true, ["miss"] = true, ["lord"] = true,
        ["lady"] = true, ["dame"] = true, ["prof"] = true, ["prof."] = true,
        ["capt"] = true, ["capt."] = true,
    }

    -- Frequency-ratio guard: if a candidate term appears 5× more often than the
    -- entity's full name in the text, it is too generic to be a useful identifier.
    -- This is language-agnostic — articles, stop words, and AI-hallucinated
    -- one-word aliases will all fail this test naturally.
    local function countInText(term)
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        local _, n = lower_text:gsub(escaped, "")
        return n
    end
    local function isTooGeneric(term, entity_name)
        if #term < 3 then return true end
        local name_freq = math.max(1, countInText(entity_name:lower()))
        return countInText(term) > name_freq * 5
    end

    -- Check if a term appears in the text surrounded by non-word characters.
    -- Pads the text so names at the very start/end of a string also match.
    local function termFound(term)
        if not term or #term < 2 then return false end
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        return (" " .. lower_text .. " "):find("[^%w]" .. escaped:lower() .. "[^%w]") ~= nil
    end

    local function scanList(list, type_name)
        if not list then return end
        for _, item in ipairs(list) do
            local name = item.name
            if name and not seen[name:lower()] then
                local found = false

                -- Strategy 1: Full name match
                if termFound(name) then
                    found = true
                end

                -- Strategy 2: First name component (e.g. "John" from "John Smith")
                if not found then
                    local first = name:match("^(%S+)")
                    if first and first ~= name
                            and not honorifics[first:lower()]
                            and not isTooGeneric(first, name) then
                        if termFound(first) then found = true end
                    end
                end

                -- Strategy 3: Last name component (e.g. "Smith" from "John Smith")
                if not found then
                    local last = name:match("(%S+)$")
                    if last and last ~= name
                            and not honorifics[last:lower()]
                            and not isTooGeneric(last, name) then
                        if termFound(last) then found = true end
                    end
                end

                -- Strategy 4: Aliases (skip generic and honorific-only aliases)
                if not found and item.aliases then
                    for _, alias in ipairs(item.aliases) do
                        if type(alias) == "string"
                                and not honorifics[alias:lower()]
                                and not isTooGeneric(alias, name)
                                and termFound(alias) then
                            found = true
                            break
                        end
                    end
                end

                if found then
                    seen[name:lower()] = true
                    table.insert(related, { item = item, type = type_name })
                end
            end
        end
    end

    scanList(self.characters, "character")
    scanList(self.locations, "location")
    scanList(self.historical_figures, "historical")

    return related
end

function M:showRelatedEntities(related)
    local items = {}
    if self.active_related_menu then
        UIManager:close(self.active_related_menu)
        self.active_related_menu = nil
    end

    for _, entry in ipairs(related) do
        local item = entry.item
        local item_type = entry.type
        local display_type = item_type:sub(1,1):upper() .. item_type:sub(2)
        table.insert(items, {
            text = (item.name or "???") .. " (" .. display_type .. ")",
            callback = function()
                -- Close both the linked entries menu and any open detail dialog
                -- before opening the new entity's detail.
                if self.active_related_menu then
                    UIManager:close(self.active_related_menu)
                    self.active_related_menu = nil
                end
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                if item_type == "character" then
                    self:showCharacterDetails(item)
                elseif item_type == "location" then
                    self:showLocationDetails(item)
                elseif item_type == "historical" then
                    self:showHistoricalFigureDetails(item)
                end
            end
        })
    end
    
    self.active_related_menu = Menu:new{
        title = self.loc:t("linked_entries") or "Linked Entries",
        item_table = items,
        on_close_callback = function()
            self.active_related_menu = nil
        end
    }
    UIManager:show(self.active_related_menu)
end

function M:showCharacterDetails(character)
    local lines = {
        (self.loc:t("label_name") or "NAME") .. ": " .. (character.name or "???")
    }
    if character.aliases and type(character.aliases) == "table" and #character.aliases > 0 then
        table.insert(lines, (self.loc:t("label_aliases") or "ALIASES") .. ": " .. table.concat(character.aliases, ", "))
    end
    table.insert(lines, (self.loc:t("label_role") or "ROLE") .. ": " .. (character.role or "---"))
    table.insert(lines, (self.loc:t("label_gender") or "GENDER") .. ": " .. (character.gender or "---"))
    table.insert(lines, (self.loc:t("label_occupation") or "OCCUPATION") .. ": " .. (character.occupation or "---"))
    table.insert(lines, "")
    table.insert(lines, (self.loc:t("label_description") or "DESCRIPTION") .. ":")
    table.insert(lines, character.description or "---")
    
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(character.description or "", character.name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        self:showMentionsForEntity(character)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = table.concat(lines, "\n"),
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = table.concat(lines, "\n"),
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    self:showMentionsForEntity(character)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = table.concat(lines, "\n"),
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showLocationDetails(loc_item)
    local name = loc_item.name or "???"
    local desc = loc_item.description or ""
    local body_text = name .. "\n\n" .. desc
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(desc, name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        self:showMentionsForEntity(loc_item)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = body_text,
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    self:showMentionsForEntity(loc_item)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showMentionsSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current_setting = self.ai_helper.settings.mentions_enabled ~= false -- default is true
        local enabled_text = self.loc:t("mentions_enabled") or "Enabled"
        local disabled_text = self.loc:t("mentions_disabled") or "Disabled"
        
        local buttons = {
            {
                {
                    text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ mentions_enabled = true })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                },
                {
                    text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ mentions_enabled = false })
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
                            text = self.loc:t("mentions_setting_desc") or "Mentions scanning allows you to find every occurrence of a character or location in the book. This happens automatically in the background to ensure the reader stays responsive.\n\nDisabling this will stop all background scanning and hide the 'Find Mentions' button.",
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
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("mentions_setting_title") or "Mentions Settings",
            text = self.loc:t("mentions_preference_desc") or "Select your preference for character and location mentions:",
            buttons = buttons,
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showLinkedEntriesSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current_setting = self.ai_helper.settings.linked_entries_enabled ~= false -- default is true
        local enabled_text = self.loc:t("linked_entries_enabled") or "Enabled"
        local disabled_text = self.loc:t("linked_entries_disabled") or "Disabled"
        
        local buttons = {
            {
                {
                    text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ linked_entries_enabled = true })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                },
                {
                    text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ linked_entries_enabled = false })
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
                            text = self.loc:t("linked_entries_setting_desc") or "Linked Entries automatically connects characters, locations, and historical figures when they are mentioned in each other's descriptions.\n\nDisabling this will hide the 'Linked Entries' button from detail dialogs.",
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
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
            buttons = buttons,
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end


function M:showAutoUpdateSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local is_enabled = self.auto_fetch_enabled
        local current_cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
            text = self.loc:t("auto_update_freq_label") or "Background fetching frequency:",
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

function M:showSpoilerSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local current_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
            text = self.loc:t("spoiler_preference_desc") or "Select your spoiler preference for X-Ray data:",
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

function M:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == (self.loc:t("msg_no_bio") or "No biography available.") then
        local ButtonDialog = require("ui/widget/buttondialog")
        local ask_dialog
        ask_dialog = ButtonDialog:new{ title = self.loc:t("menu_fetch_author") or "Fetch Author Info", text = self.loc:t("no_author_data_fetch"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(ask_dialog) end }, { text = self.loc:t("fetch_button") or "Fetch", is_enter_default = true, callback = function() UIManager:close(ask_dialog); UIManager:nextTick(function() self:fetchAuthorInfo() end) end }}} }
        UIManager:show(ask_dialog); return
    end
    local lines = { "NAME: " .. (self.author_info.name or "Unknown"), "BORN: " .. (self.author_info.birthDate or "---"), "DIED: " .. (self.author_info.deathDate or "---"), "", "BIOGRAPHY:", (self.author_info.description or "No biography available.") }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 30 })
end

function M:showLocations()
    if not self.locations or #self.locations == 0 then 
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return 
    end
    local items = {}
    for _, loc in ipairs(self.locations) do 
        if type(loc) == "table" then
            local captured_loc = loc
            table.insert(items, {
                text = loc.name or "???",
                keep_menu_open = true,
                callback = function()
                    self:showLocationDetails(captured_loc)
                end
            })
        end
    end
    
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return
    end
    
    self.loc_menu = Menu:new{
        title = self.loc:t("menu_locations"),
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.loc_menu)
end

function M:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    local version = meta.version or "?.?.?"
    local description = self.loc:t("plugin_description") or tostring(meta.description or "")

    local body = (meta.fullname or "X-Ray") .. " v" .. version .. "\n\n" .. description

    UIManager:show(ConfirmBox:new{
        text = body,
        icon = "lightbulb",
        ok_text = self.loc:t("updater_check") or "Check for Updates",
        cancel_text = self.loc:t("close") or "Close",
        ok_callback = function()
            local updater = require(plugin_path .. "xray_updater")
            updater.checkForUpdates(self.loc)
        end,
    })
end

function M:clearCache()
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}; self.locations = {}; self.timeline = {}; self.historical_figures = {}; self.author_info = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function M:clearLogs()
    local XRayLogger = require(plugin_path .. "xray_logger")
    XRayLogger:clear()
    UIManager:show(InfoMessage:new{ text = self.loc:t("logs_cleared") or "Logs cleared!", timeout = 3 })
end

function M:toggleXRayMode()
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

function M:showTimeline()
    if not self.timeline or #self.timeline == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 }); return end
    local toc = self.ui.document:getToc()
    self:assignTimelinePages(self.timeline, toc, true)
    self:sortTimelineByTOC(self.timeline)
    local items = {}
    for _, ev in ipairs(self.timeline) do
        table.insert(items, {
            text = (ev.chapter or "") .. ": " .. (ev.event or ""),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{ text = (ev.event or ""), timeout = 10 })
            end
        })
    end
    self.timeline_menu = Menu:new{ 
        title = self.loc:t("menu_timeline"), 
        item_table = items, 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.timeline_menu)
end

function M:showHistoricalFigureDetails(fig)
    local name = fig.name or "???"
    local bio = fig.biography or (self.loc:t("msg_no_bio") or "No biography available.")
    local body_text = name .. "\n\n" .. bio
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(bio, name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        self:showMentionsForEntity(fig)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = body_text,
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    self:showMentionsForEntity(fig)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showHistoricalFigures()
    if not self.historical_figures or #self.historical_figures == 0 then 
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 })
        return 
    end
    local items = {}
    for _, fig in ipairs(self.historical_figures) do
        table.insert(items, {
            text = (fig.name or "???"),
            keep_menu_open = true,
            callback = function()
                self:showHistoricalFigureDetails(fig)
            end,
        })
    end

    self.hf_menu = Menu:new{
        title = self.loc:t("menu_historical_figures"), 
        item_table = items, 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.hf_menu)
end

function M:showQuickXRayMenu() self:showFullXRayMenu() end
function M:showFullXRayMenu()
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

function M:getAPIKeySelectionMenu(provider, provider_name)
    local config_key = (self.ai_helper and self.ai_helper.config_keys) and self.ai_helper.config_keys[provider] or nil
    
    local menu_items = {
        {
            text = "Use key from config.lua: " .. (config_key and #config_key > 0 and config_key or "(Not set)"),
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return not self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = false })
                self.ai_helper:init(self.path)
                UIManager:setDirty(nil, "ui")
            end
        },
        {
            text = (self.loc:t("menu_enter_ui_key") or "Enter UI override key: ") .. ((self.ai_helper and self.ai_helper.settings and self.ai_helper.settings[provider .. "_api_key"]) or "(Not set)"),
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                local ui_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or nil
                
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

function M:getAIModelSelectionMenu(setting_type)
    local models = {
        { name = "Gemini Flash (gemini-2.5-flash) - " .. (self.loc:t("model_free") or "free"), provider = "gemini", id = "gemini-2.5-flash" },
        { name = "Gemini Flash-Lite (gemini-2.5-flash-lite) - " .. (self.loc:t("model_free") or "free"), provider = "gemini", id = "gemini-2.5-flash-lite" },
        { name = "Gemini Pro (gemini-2.5-pro) - " .. (self.loc:t("model_paid") or "paid"), provider = "gemini", id = "gemini-2.5-pro" },
        { name = "ChatGPT Mini (gpt-4o-mini) - " .. (self.loc:t("model_paid") or "paid"), provider = "chatgpt", id = "gpt-4o-mini" },
        { name = "ChatGPT (gpt-4o) - " .. (self.loc:t("model_paid") or "paid"), provider = "chatgpt", id = "gpt-4o" },
    }
    
    local menu_items = {}
    for i, m in ipairs(models) do
        table.insert(menu_items, {
            text = m.name,
            checked_func = function()
                if not self.ai_helper or not self.ai_helper.settings then return false end
                local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                if type(current) ~= "table" then return false end
                return current.provider == m.provider and current.model == m.id
            end,
            callback = function()
                self.ai_helper:setUnifiedModel(setting_type, m.provider, m.id)
                UIManager:setDirty(nil, "ui")
            end
        })
        if i == #models then
            menu_items[#menu_items].separator = true
        end
    end
    table.insert(menu_items, {
        text = self.loc:t("menu_enter_custom_model") or "Enter custom model...",
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            local current = (self.ai_helper and self.ai_helper.settings) and (setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai) or nil
            input_dialog = InputDialog:new{
                title = (self.loc:t("menu_custom_model_title") or "Custom %s Model"):format(setting_type:gsub("^%l", string.upper)),
                input = current and current.model or "",
                input_hint = "e.g., gemini-2.5-pro",
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

function M:findCharacterByName(word)
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

function M:showCharacterSearch()
    if not self.characters or #self.characters == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("search_character_title"), input = "", input_hint = self.loc:t("search_hint"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("search_button"), is_enter_default = true, callback = function() local search_text = input_dialog:getInputText(); UIManager:close(input_dialog); if search_text and #search_text > 0 then local found_char = self:findCharacterByName(search_text); if found_char then self:showCharacterDetails(found_char) else UIManager:show(InfoMessage:new{ text = self.loc:t("character_not_found", search_text), timeout = 3 }) end end end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function M:showConfigSummary()
    local text = (self.loc:t("menu_config_header") or "--- Current Configuration ---") .. "\n\n"
    
    local primary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.primary_ai or nil
    local secondary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.secondary_ai or nil
    
    local primary_label = self.loc:t("menu_primary_ai_model") or "Primary AI Model"
    local secondary_label = self.loc:t("menu_secondary_ai_model") or "Secondary AI Model"
    local provider_label = self.loc:t("config_provider") or "  Provider: "
    local model_label = self.loc:t("config_model") or "  Model: "
    local default_label = self.loc:t("config_default_gemini") or "  Default (Gemini)"
    local set_label = self.loc:t("config_status_set") or "SET"
    local not_set_label = self.loc:t("config_status_not_set") or "NOT SET"

    text = text .. primary_label .. ":\n"
    if primary then 
        text = text .. provider_label .. primary.provider .. "\n" .. model_label .. primary.model .. "\n\n" 
    else 
        text = text .. default_label .. "\n\n" 
    end
    
    text = text .. secondary_label .. ":\n"
    if secondary then 
        text = text .. provider_label .. secondary.provider .. "\n" .. model_label .. secondary.model .. "\n\n" 
    else 
        text = text .. default_label .. "\n\n" 
    end
    
    local function add(p, n)
        local c = self.ai_helper.providers[p]
        local key_label = (self.loc:t("config_api_key_label") or "%s API Key: "):format(n)
        text = text .. key_label .. (c.api_key and set_label or not_set_label) .. "\n"
    end
    add("gemini", "Google Gemini"); add("chatgpt", "ChatGPT")
    
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end

function M:checkWeeklyUpdate()
    if not self.ai_helper or not self.ai_helper.settings then return end
    
    local last_check = self.ai_helper.settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    
    if (now - last_check) > week_seconds then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isOnline() then
            self:log("XRayPlugin: Triggering weekly silent update check")
            self.ai_helper:saveSettings({ last_update_check = now })
            local updater = require(plugin_path .. "xray_updater")
            updater.checkSilentForUpdates(self.loc)
        else
            self:log("XRayPlugin: Skipping weekly update check (offline)")
        end
    end
end

return M
