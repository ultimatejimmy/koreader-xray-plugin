-- X-Ray Mentions Logic and UI

local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local XRayConfig = require(plugin_path .. "xray_config")


local M = {}

function M:buildMentionsInBackground(is_from_fetch)
    if not self.ui or not self.ui.document then return end
    if self.mentions_scan_active then return end

    local toc = self.ui.document:getToc()
    if not toc or #toc == 0 then return end

    local spoiler_free = (self.ai_helper and self.ai_helper.settings
        and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local max_page = spoiler_free and self.ui:getCurrentPage() or nil

    -- Capture activated entities (those with existing cached mentions) BEFORE
    -- resetting them. Dormant entities wait for the manual "Find Mentions" trigger.
    local queue = {}
    for _, c in ipairs(self.characters or {}) do
        if c.name and c.mentions and #c.mentions > 0 then
            table.insert(queue, { entity = c, name = c.name })
            c.mentions = nil  -- reset only activated entities for a fresh scan
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
    self:log("XRayPlugin: Background mentions update for " .. #queue .. " activated entities")
    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end

    local idx = 1
    local function scanNext()
        if not self.ui or not self.ui.document then
            self.mentions_scan_active = false; return
        end
        if idx > #queue then
            self.mentions_scan_active = false
            self:log("XRayPlugin: Background mentions scan complete")
            self:saveMentionsToCache()
            return
        end
        
        local item = queue[idx]
        idx = idx + 1
        
        -- Use the new fully asynchronous scanner for background work
        self.bg_scan_handle = self.chapter_analyzer:scanMentionsAsync(
            self.ui, item.entity, toc, max_page,
            nil, -- no progress callback for silent background work
            function(result)
                if result then item.entity.mentions = result end
                -- Yield between entities
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
    -- Early-exit
    local has_activated = false
    for _, c in ipairs(self.characters or {}) do
        if c.mentions and #c.mentions > 0 then has_activated = true; break end
    end
    if not has_activated then
        for _, l in ipairs(self.locations or {}) do
            if l.mentions and #l.mentions > 0 then has_activated = true; break end
        end
    end
    if not has_activated then
        for _, h in ipairs(self.historical_figures or {}) do
            if h.mentions and #h.mentions > 0 then has_activated = true; break end
        end
    end
    if not has_activated then return end

    local all_entities = {}
    for _, c in ipairs(self.characters or {}) do
        if c.name then table.insert(all_entities, c) end
    end
    for _, l in ipairs(self.locations or {}) do
        if l.name then table.insert(all_entities, l) end
    end
    for _, h in ipairs(self.historical_figures or {}) do
        if h.name then table.insert(all_entities, h) end
    end
    if #all_entities == 0 then return end

    self:log("XRayPlugin: Incremental mentions scan for: " .. (toc_entry.title or "?"))
    local idx = 1
    local changed = false
    local function scanNext()
        if not self.ui or not self.ui.document then return end
        if idx > #all_entities then
            if changed then self:saveMentionsToCache() end
            return
        end
        local entity = all_entities[idx]; idx = idx + 1
        
        -- ONLY scan entities that are already activated with mentions
        if not entity.mentions or #entity.mentions == 0 then
            UIManager:scheduleIn(0, scanNext)
            return
        end
        
        local ok, result = pcall(function()
            return self.chapter_analyzer:findMentionsInChapter(
                self.ui, entity, toc_entry, next_toc_entry)
        end)
        if ok and result and #result > 0 then
            entity.mentions = entity.mentions or {}
            for _, new_m in ipairs(result) do
                local already = false
                for _, m in ipairs(entity.mentions) do
                    -- Simple duplicate check: same page and snippet start
                    if m.page == new_m.page and m.snippet == new_m.snippet then
                        already = true; break
                    end
                end
                if not already then
                    table.insert(entity.mentions, new_m)
                    changed = true
                end
            end
            if changed then
                table.sort(entity.mentions, function(a, b)
                    return (a.page or 0) < (b.page or 0)
                end)
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
    if not self.ui or not self.ui.document then return end
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
    collectgarbage("collect")
    self.cache_manager:saveCache(self.ui.document.file, updated)
    self:log("XRayPlugin: Mentions saved to cache")
end

function M:showMentionsForEntity(entity)
    if not entity then return end
    
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled
    if mentions_enabled == false then return end
    
    local name = entity.name or "???"
    
    if self.active_mention_scan and self.active_mention_scan.entity_name == name then
        self:showMentionsMenu(entity)
        return
    end

    if entity.mentions and #entity.mentions > 0 then
        self:showMentionsMenu(entity)
        return
    end

    if not self.ui or not self.ui.document then return end
    
    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end
    
    local toc = self.ui.document:getToc() or {}
    local spoiler_free = (self.ai_helper and self.ai_helper.settings
        and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local max_page = spoiler_free and self.ui:getCurrentPage() or nil
    
    self.active_mention_scan = {
        entity_name = name,
        chapter_idx = 0,
        total_chapters = #toc,
        cancel_handle = nil
    }
    
    self.active_mention_scan.cancel_handle = self.chapter_analyzer:scanMentionsAsync(
        self.ui, entity, toc, max_page,
        function(mentions_so_far, chapter_idx, total_chapters)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                self.active_mention_scan.chapter_idx = chapter_idx
                self.active_mention_scan.total_chapters = total_chapters
                if self.mentions_menu then
                    entity.mentions = mentions_so_far
                    self:updateMentionsMenuInPlace(entity)
                end
            end
        end,
        function(all_mentions)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                self.active_mention_scan = nil
            end
            entity.mentions = all_mentions
            self:saveMentionsToCache()
            if self.mentions_menu then
                self:updateMentionsMenuInPlace(entity)
            end
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
        local scan_text = (self.loc:t("mentions_scanning") or "Scanning... %1 of %2 chapters")
            :gsub("%%1", tostring(self.active_mention_scan.chapter_idx))
            :gsub("%%2", tostring(self.active_mention_scan.total_chapters))
        table.insert(items, {
            text = "\xE2\x8F\xB3 " .. scan_text,
            keep_menu_open = true,
            callback = function() end,
        })
        
        table.insert(items, {
            text = "\xe2\x9a\xa0 " .. (self.loc:t("mentions_wait_scan") or "Wait for scan to finish before navigating..."),
            keep_menu_open = true,
            callback = function() end,
        })
        
        table.insert(items, {
            text = "\xE2\x9C\x96 " .. (self.loc:t("close") or "Close"),
            keep_menu_open = true,
            callback = function()
                if self.mentions_menu then
                    UIManager:close(self.mentions_menu)
                    self.mentions_menu = nil
                end
            end,
            separator = true,
        })
    else
        table.insert(items, {
            text = "\xe2\x86\xba " .. (self.loc:t("mentions_refresh") or "Refresh Mentions"),
            keep_menu_open = true,
            callback = function()
                entity.mentions = {}
                if self.active_mention_scan and self.active_mention_scan.cancel_handle then
                    self.active_mention_scan.cancel_handle:cancel()
                end
                
                local toc = self.ui.document:getToc() or {}
                local spoiler_free = (self.ai_helper and self.ai_helper.settings
                    and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
                local max_page = spoiler_free and self.ui:getCurrentPage() or nil
                
                if not self.chapter_analyzer then
                    self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
                end
                
                self.active_mention_scan = {
                    entity_name = name,
                    chapter_idx = 0,
                    total_chapters = #toc,
                    cancel_handle = nil
                }
                
                self.active_mention_scan.cancel_handle = self.chapter_analyzer:scanMentionsAsync(
                    self.ui, entity, toc, max_page,
                    function(mentions_so_far, chapter_idx, total_chapters)
                        if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                            self.active_mention_scan.chapter_idx = chapter_idx
                            self.active_mention_scan.total_chapters = total_chapters
                            if self.mentions_menu and (chapter_idx % 10 == 0 or chapter_idx == total_chapters) then
                                entity.mentions = mentions_so_far
                                self:updateMentionsMenuInPlace(entity)
                            end
                        end
                    end,
                    function(all_mentions)
                        if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                            self.active_mention_scan = nil
                        end
                        entity.mentions = all_mentions
                        self:saveMentionsToCache()
                        if self.mentions_menu then
                            self:updateMentionsMenuInPlace(entity)
                        end
                    end
                )
                self:updateMentionsMenuInPlace(entity)
            end,
            separator = true,
        })
    end

    if not is_scanning and (#mentions == 0) then
        table.insert(items, {
            text = (self.loc:t("mentions_none") or "No mentions found for '%s' yet."):format(name),
            keep_menu_open = true,
            callback = function() end,
        })
        return items
    end

    table.sort(mentions, function(a, b) return (a.page or 0) < (b.page or 0) end)

    for _, m in ipairs(mentions) do
        local pg = m.page
        local header = "p." .. tostring(pg) .. " \xE2\x80\x94 " .. (m.chapter or "")
        
        local snippet = m.snippet or ""
        if #snippet > 100 then
            snippet = snippet:sub(1, 100):gsub("%s%S*$", "") .. "…"
        end
        local snip   = (snippet ~= "") and ("\n" .. snippet) or ""
        
        table.insert(items, {
            text = header .. snip,
            keep_menu_open = true,
            callback = function()
                if is_scanning then return end
                if self.mentions_menu then UIManager:close(self.mentions_menu) end
                
                UIManager:nextTick(function()
                    self:closeAllMenus()
                    
                    UIManager:nextTick(function()
                        local Event = require("ui/event")
                        self.ui:handleEvent(Event:new("GotoPage", pg))
                    end)
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
    if self.mentions_menu.switchItemTable then
        pcall(function()
            self.mentions_menu:switchItemTable(title, items)
        end)
    end
end

function M:showMentionsMenu(entity)
    if not entity then return end
    local name = entity.name or "???"
    local items = self:buildMentionsMenuItems(entity)

    self.mentions_menu = Menu:new{
        title          = (self.loc:t("mentions_title") or "Mentions: %s"):format(name),
        item_table     = items,
        is_borderless  = true,
        width          = Screen:getWidth(),
        height         = Screen:getHeight(),
        on_close_callback = function() 
            self.mentions_menu = nil
        end,
    }
    UIManager:show(self.mentions_menu)
end

return M
