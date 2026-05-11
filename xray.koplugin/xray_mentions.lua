-- X-Ray Mentions Logic and UI

local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local Font = require("ui/font")
local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local XRayConfig = require(plugin_path .. "xray_config")


local M = {}

-- Safe helper for current page
local function _getCurrentPage(plugin)
    if plugin.last_pageno then return plugin.last_pageno end
    if plugin.ui and plugin.ui.paging and plugin.ui.paging.getCurrentPage then
        local ok, pg = pcall(function() return plugin.ui.paging:getCurrentPage() end)
        if ok then return pg end
    end
    if plugin.ui and plugin.ui.pageno then
        return plugin.ui.pageno
    end
    return 1
end

function M:buildMentionsInBackground(is_from_fetch)
    if not self.ui or not self.ui.document then return end
    if self.mentions_scan_active then return end

    local toc = self.ui.document:getToc()
    if not toc or #toc == 0 then return end

    local spoiler_free = (self.ai_helper and self.ai_helper.settings
        and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local max_page = spoiler_free and _getCurrentPage(self) or nil

    local queue = {}
    for _, c in ipairs(self.characters or {}) do
        if c.name and c.mentions and #c.mentions > 0 then
            table.insert(queue, { entity = c, name = c.name })
            c.mentions = nil
        end
    end
    for _, l in ipairs(self.locations or {}) do
        if l.name and l.mentions and #l.mentions > 0 then
            table.insert(queue, { entity = l, name = l.name })
            l.mentions = nil
        end
    end
    for _, h in ipairs(self.historical_figures or {}) do
        if h.name and h.mentions and #h.mentions > 0 then
            table.insert(queue, { entity = h, name = h.name })
            h.mentions = nil
        end
    end
    if #queue == 0 then return end

    self.mentions_scan_active = true
    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end

    local idx = 1
    local function scanNext()
        if not self.ui or not self.ui.document then self.mentions_scan_active = false; return end
        if idx > #queue then
            self.mentions_scan_active = false
            self:saveMentionsToCache()
            return
        end
        
        local item = queue[idx]; idx = idx + 1
        self.bg_scan_handle = self.chapter_analyzer:scanMentionsAsync(
            self.ui, item.entity, toc, max_page,
            nil,
            function(result)
                if result then item.entity.mentions = result end
                UIManager:scheduleIn(0.5, scanNext)
            end
        )
    end
    UIManager:scheduleIn(is_from_fetch and 3 or 1, scanNext)
end

function M:updateMentionsForChapter(toc_entry, next_toc_entry)
    if not self.ui or not self.ui.document then return end
    if self.mentions_scan_active then return end
    if not toc_entry then return end
    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end
    
    local all_entities = {}
    for _, c in ipairs(self.characters or {}) do if c.name then table.insert(all_entities, c) end end
    for _, l in ipairs(self.locations or {}) do if l.name then table.insert(all_entities, l) end end
    for _, h in ipairs(self.historical_figures or {}) do if h.name then table.insert(all_entities, h) end end
    if #all_entities == 0 then return end

    local idx = 1
    local changed = false
    local function scanNext()
        if not self.ui or not self.ui.document then return end
        if idx > #all_entities then
            if changed then self:saveMentionsToCache() end
            return
        end
        local entity = all_entities[idx]; idx = idx + 1
        if not entity.mentions or #entity.mentions == 0 then
            UIManager:scheduleIn(0, scanNext); return
        end
        
        local ok, result = pcall(function()
            return self.chapter_analyzer:findMentionsInChapter(self.ui, entity, toc_entry, next_toc_entry)
        end)
        if ok and result and #result > 0 then
            entity.mentions = entity.mentions or {}
            for _, new_m in ipairs(result) do
                local already = false
                for _, m in ipairs(entity.mentions) do
                    if m.page == new_m.page and m.snippet == new_m.snippet then already = true; break end
                end
                if not already then table.insert(entity.mentions, new_m); changed = true end
            end
            if changed then
                table.sort(entity.mentions, function(a, b) return (a.page or 0) < (b.page or 0) end)
            end
        end
        UIManager:scheduleIn(0.1, scanNext)
    end
    UIManager:scheduleIn(0, scanNext)
end

function M:saveMentionsToCache()
    if not self.cache_manager then
        self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
    end
    local updated = {
        book_title         = self.book_data and self.book_data.book_title,
        author             = self.book_data and self.book_data.author,
        characters         = self.characters,
        historical_figures = self.historical_figures,
        locations          = self.locations,
        timeline           = self.timeline,
        author_info        = self.author_info,
        last_fetch_page    = self.book_data and self.book_data.last_fetch_page,
    }
    self.cache_manager:saveCache(self.ui.document.file, updated)
end

function M:showMentionsForEntity(entity)
    if not entity then return end
    local name = entity.name or "???"
    if (self.active_mention_scan and self.active_mention_scan.entity_name == name) or (entity.mentions and #entity.mentions > 0) then
        self:showMentionsMenu(entity); return
    end
    if not self.ui or not self.ui.document then return end
    if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
    
    local toc = self.ui.document:getToc() or {}
    local spoiler_free = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local max_page = spoiler_free and _getCurrentPage(self) or nil
    
    self.active_mention_scan = { entity_name = name, chapter_idx = 0, total_chapters = #toc, cancel_handle = nil }
    self.active_mention_scan.cancel_handle = self.chapter_analyzer:scanMentionsAsync(
        self.ui, entity, toc, max_page,
        function(mentions_so_far, chapter_idx, total_chapters)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                self.active_mention_scan.chapter_idx = chapter_idx
                self.active_mention_scan.total_chapters = total_chapters
                if self.mentions_menu then entity.mentions = mentions_so_far; self:updateMentionsMenuInPlace(entity) end
            end
        end,
        function(all_mentions)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then self.active_mention_scan = nil end
            entity.mentions = all_mentions
            self:saveMentionsToCache()
            if self.mentions_menu then self:updateMentionsMenuInPlace(entity) end
        end
    )
    self:showMentionsMenu(entity)
end

function M:buildMentionsMenuItems(entity)
    local items = {}
    local name = entity.name or "???"
    local mentions = entity.mentions or {}
    local is_scanning = self.active_mention_scan and self.active_mention_scan.entity_name == name
    
    if is_scanning then
        local scan_text = (self.loc:t("mentions_scanning") or "Scanning... %1 of %2 chapters"):gsub("%%1", tostring(self.active_mention_scan.chapter_idx)):gsub("%%2", tostring(self.active_mention_scan.total_chapters))
        table.insert(items, { text = "\xE2\x8F\xB3 " .. scan_text, keep_menu_open = true, callback = function() end })
        table.insert(items, { text = "\xE2\x9C\x96 " .. (self.loc:t("close") or "Close"), keep_menu_open = true, callback = function() if self.mentions_menu then UIManager:close(self.mentions_menu); self.mentions_menu = nil end end, separator = true })
    else
        table.insert(items, { text = "\xe2\x86\xba " .. (self.loc:t("mentions_refresh") or "Refresh Mentions"), keep_menu_open = true, callback = function()
            entity.mentions = {}; if self.active_mention_scan and self.active_mention_scan.cancel_handle then self.active_mention_scan.cancel_handle:cancel() end
            self:showMentionsForEntity(entity)
        end, separator = true })
    end

    if not is_scanning and (#mentions == 0) then
        table.insert(items, { text = (self.loc:t("mentions_none") or "No mentions found for '%s' yet."):format(name), keep_menu_open = true, callback = function() end })
        return items
    end

    table.sort(mentions, function(a, b) return (a.page or 0) < (b.page or 0) end)

    for _, m in ipairs(mentions) do
        local pg = m.page
        local snippet = m.snippet or ""
        if #snippet > 100 then snippet = snippet:sub(1, 100):gsub("%s%S*$", "") .. "…" end
        table.insert(items, {
            text = "p." .. tostring(pg) .. " \xE2\x80\x94 " .. (m.chapter or "") .. ((snippet ~= "") and ("\n" .. snippet) or ""),
            keep_menu_open = true,
            callback = function()
                if is_scanning then return end
                local return_pg = self.return_page_origin or _getCurrentPage(self)
                self.return_page_origin = return_pg
                
                self.pending_return_banner = {
                    return_page = return_pg,
                    entity_name = name,
                    mentions = mentions
                }
                
                self:closeAllMenus()
                UIManager:nextTick(function()
                    self.ui:handleEvent(Event:new("GotoPage", pg))
                end)
            end,
        })
    end
    return items
end

function M:updateMentionsMenuInPlace(entity)
    if not self.mentions_menu then return end
    local items = self:buildMentionsMenuItems(entity)
    local name = entity.name or "???"
    local title = (self.loc:t("mentions_title") or "Mentions: %s"):format(name)
    if self.mentions_menu.switchItemTable then pcall(function() self.mentions_menu:switchItemTable(title, items) end) end
end

function M:showMentionsMenu(entity)
    if not entity then return end
    self.mentions_menu = Menu:new{
        title = (self.loc:t("mentions_title") or "mentions_title"):format(entity.name or "???"),
        item_table = self:buildMentionsMenuItems(entity),
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function() self.mentions_menu = nil end,
    }
    UIManager:show(self.mentions_menu)
end

function M:showReturnBanner(return_page, entity_name, mentions, current_page)
    if self.return_banner then UIManager:close(self.return_banner); self.return_banner = nil end

    local plugin = self
    local title = (self.loc:t("mentions_at_location") or "Mention: %s"):format(entity_name)
    
    local unique_pages = {}
    local page_to_idx = {}
    if mentions then
        for _, m in ipairs(mentions) do
            if m.page and not page_to_idx[m.page] then
                table.insert(unique_pages, m.page)
                page_to_idx[m.page] = #unique_pages
            end
        end
    end
    local current_pg_idx = page_to_idx[current_page] or 1
    local prev_enabled = current_pg_idx > 1
    local next_enabled = current_pg_idx < #unique_pages

    -- ButtonDialog is stable. To fix "pretty" and "middle", we customize it.
    local buttons = {{
        {
            text = prev_enabled and "\xE2\x97\x80" or "\xE2\x94\x81", -- Arrow vs Bar
            callback = function()
                if not prev_enabled then return end
                local prev_pg = unique_pages[current_pg_idx - 1]
                plugin.pending_return_banner = { return_page = return_page, entity_name = entity_name, mentions = mentions }
                plugin:_doReturnJump(prev_pg)
            end,
        },
        {
            text = (self.loc:t("back_to_reading") or "Back"),
            callback = function() plugin:_doReturnJump(return_page) end,
        },
        {
            text = "\xE2\x9C\x95", -- Close icon
            callback = function()
                if plugin.return_banner then UIManager:close(plugin.return_banner); plugin.return_banner = nil; plugin.return_page_origin = nil end
            end,
        },
        {
            text = next_enabled and "\xE2\x96\xB6" or "\xE2\x94\x81",
            callback = function()
                if not next_enabled then return end
                local next_pg = unique_pages[current_pg_idx + 1]
                plugin.pending_return_banner = { return_page = return_page, entity_name = entity_name, mentions = mentions }
                plugin:_doReturnJump(next_pg)
            end,
        },
    }}

    self.return_banner = ButtonDialog:new{
        title = title,
        buttons = buttons,
        is_borderless = true,
        width = Screen:getWidth(),
        show_close_button = false,
        on_close_callback = function() plugin.return_banner = nil end,
    }
    
    -- STABILITY SECRET: Override recenter to force it to the bottom
    self.return_banner.recenter = function(this)
        this:moveTo(0, Screen:getHeight() - this:getHeight())
    end
    
    UIManager:show(self.return_banner)
end

function M:_doReturnJump(return_page)
    if not return_page then return end
    if self.return_banner then UIManager:close(self.return_banner); self.return_banner = nil; self.return_page_origin = nil end
    self.ui:handleEvent(Event:new("GotoPage", return_page))
end

return M