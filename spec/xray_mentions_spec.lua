-- xray_mentions_spec.lua
require("spec/spec_helper")
local xray_mentions = require("xray_mentions")
local xray_ui = require("xray_ui")

describe("xray_mentions", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        for k, v in pairs(xray_mentions) do plugin[k] = v end
        plugin.closeAllMenus = xray_ui.closeAllMenus
        _G.ui_tracker.shown = {}; _G.ui_tracker.last_shown = nil; _G.ui_tracker.closed = {}
    end)

    describe("showReturnBanner", function()
        local test_mentions = { {page = 10}, {page = 20}, {page = 30} }

        it("should show a ButtonDialog for return navigation", function()
            plugin:showReturnBanner(5, "Frodo", test_mentions, 20)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
        end)
    end)

    describe("Jump Logic with Flag", function()
        it("should set the pending_return_banner flag instead of showing immediately", function()
            plugin.last_pageno = 100
            local entity = { name = "Frodo", mentions = { {page = 10} } }
            local items = plugin:buildMentionsMenuItems(entity)
            local mention_item = nil
            for _, itm in ipairs(items) do
                if itm.text:find("p.10") then mention_item = itm; break end
            end
            
            mention_item.callback()
            assert.is_not_nil(plugin.pending_return_banner)
            assert.are.equal(100, plugin.pending_return_banner.return_page)
            assert.is_nil(_G.ui_tracker.last_shown)
        end)
    end)
end)
