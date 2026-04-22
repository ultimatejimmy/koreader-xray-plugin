-- LookupManager - Core logic for text selection lookups
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local LookupManager = {}

function LookupManager:new(plugin)
    local o = {
        plugin = plugin
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Clean and normalize text for comparison
function LookupManager:normalize(text)
    if not text then return "" end
    -- Remove non-alphanumeric characters from start/end and lowercase
    local clean = text:gsub("^[^%w]+", ""):gsub("[^%w]+$", ""):lower()
    return clean
end

-- Collect all matches from a category list using a test function.
-- Returns a list of {item, type} tables. Skips items already seen (by name).
local function collectMatches(categories, seen, testFn)
    local results = {}
    for _, cat in ipairs(categories) do
        if cat.list then
            for _, item in ipairs(cat.list) do
                if item.name then
                    local norm = item.name:lower()
                    if not seen[norm] and testFn(item.name, cat) then
                        seen[norm] = true
                        table.insert(results, { item = item, item_type = cat.type })
                    end
                end
            end
        end
    end
    return results
end

-- Perform a robust lookup and return ALL matching candidates, prioritised by
-- pass quality (exact → contains query → query contained in name → keyword).
-- Returns a list of {item, item_type}, which may be empty.
function LookupManager:lookupAll(text)
    if not text or text == "" then return {} end
    local query = self:normalize(text)
    if #query < 2 then return {} end

    local categories = {
        { list = self.plugin.characters,        type = "character"  },
        { list = self.plugin.historical_figures, type = "historical" },
        { list = self.plugin.locations,         type = "location"   },
    }

    local seen = {}  -- tracks already-added names across passes

    -- Pass 1: Exact match
    local results = collectMatches(categories, seen, function(name)
        return self:normalize(name) == query
    end)
    if #results > 0 then return results end

    -- Pass 2: The selected text contains a full item name (≥3 chars)
    results = collectMatches(categories, seen, function(name)
        local norm = self:normalize(name)
        return #norm >= 3 and query:find(norm, 1, true)
    end)
    if #results > 0 then return results end

    -- Pass 3: The item name contains the selected text
    results = collectMatches(categories, seen, function(name)
        return self:normalize(name):find(query, 1, true) ~= nil
    end)
    if #results > 0 then return results end

    -- Pass 4: Keyword matching — any word in the query is a significant part of a name
    local words = {}
    for word in query:gmatch("[%w%z\128-\255]+") do
        if #word >= 3 then table.insert(words, word) end
    end

    if #words > 0 then
        results = collectMatches(categories, seen, function(name)
            local norm = self:normalize(name)
            for _, w in ipairs(words) do
                if norm == w
                    or norm:find("^" .. w .. " ")
                    or norm:find(" "  .. w .. "$")
                    or norm:find(" "  .. w .. " ") then
                    return true
                end
            end
            return false
        end)
    end

    return results
end

-- Convenience single-result wrapper used by callers that don't need disambiguation
function LookupManager:lookup(text)
    local all = self:lookupAll(text)
    if #all == 0 then return nil, nil end
    return all[1].item, all[1].item_type
end

-- Dispatch a single result to the appropriate UI handler
function LookupManager:showResult(item, item_type)
    if item_type == "character" then
        self.plugin:showCharacterDetails(item)
    elseif item_type == "historical" then
        local name = item.name or "???"
        local bio  = item.biography or "No biography available."
        UIManager:show(InfoMessage:new{ text = name .. "\n\n" .. bio, timeout = 15 })
    elseif item_type == "location" then
        local name = item.name or "???"
        local desc = item.description or ""
        UIManager:show(InfoMessage:new{ text = name .. "\n\n" .. desc, timeout = 10 })
    end
end

-- Handle the UI part of the lookup, with a disambiguation picker for multiple hits
function LookupManager:handleLookup(text)
    if not text or text == "" then return end

    local all = self:lookupAll(text)

    if #all == 1 then
        -- Unambiguous — show directly
        self:showResult(all[1].item, all[1].item_type)

    elseif #all > 1 then
        -- Multiple candidates — let the user pick
        local ButtonDialog = require("ui/widget/buttondialog")
        local prompt = self.plugin.loc:t("multiple_matches", text:sub(1, 30))
        local buttons = {}
        local dialog

        for _, candidate in ipairs(all) do
            local display_name = candidate.item.name or "???"
            -- Capture loop vars for the closure
            local captured_item = candidate.item
            local captured_type = candidate.item_type
            table.insert(buttons, {
                {
                    text = display_name,
                    callback = function()
                        UIManager:close(dialog)
                        self:showResult(captured_item, captured_type)
                    end,
                }
            })
        end

        -- Cancel row
        table.insert(buttons, {
            {
                text = self.plugin.loc:t("close") or "Close",
                callback = function()
                    UIManager:close(dialog)
                end,
            }
        })

        dialog = ButtonDialog:new{
            title = prompt,
            buttons = buttons,
        }
        UIManager:show(dialog)

    else
        -- No match found
        local has_data = (self.plugin.characters        and #self.plugin.characters        > 0) or
                         (self.plugin.historical_figures and #self.plugin.historical_figures > 0) or
                         (self.plugin.locations          and #self.plugin.locations          > 0)

        if not has_data then
            local ConfirmBox = require("ui/widget/confirmbox")
            local no_data_dialog
            no_data_dialog = ConfirmBox:new{
                text       = self.plugin.loc:t("no_data_prompt"),
                ok_text    = self.plugin.loc:t("fetch_button") or "Fetch",
                cancel_text = self.plugin.loc:t("close") or "Close",
                ok_callback = function()
                    self.plugin:fetchFromAI()
                end,
                cancel_callback = function()
                    UIManager:close(no_data_dialog)
                end,
            }
            UIManager:show(no_data_dialog)
        else
            UIManager:show(InfoMessage:new{
                text    = string.format("No X-Ray data found for '%s'", text:sub(1, 30)),
                timeout = 3,
            })
        end
    end
end

return LookupManager
