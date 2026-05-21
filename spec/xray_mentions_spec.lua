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

        it("should paint scroll highlights when paintTo is called on the banner's wrapper", function()
            local mock_child = {
                getSize = function() return { w = 100, h = 50 } end,
                paintTo = function() end
            }
            local button_dialog_new = package.loaded["ui/widget/buttondialog"].new
            package.loaded["ui/widget/buttondialog"].new = function(a, b)
                local dialog = button_dialog_new(a, b)
                dialog[1] = { mock_child, dimen = { x = 0, y = 0, w = 600, h = 100 } }
                dialog.movable = { dimen = { x = 0, y = 0, w = 600, h = 100 } }
                dialog.dimen = dialog.movable.dimen
                return dialog
            end

            plugin.scroll_highlight_boxes = {
                { x = 10, y = 20, w = 100, h = 15 }
            }
            plugin._banner_natural_h = 100

            local darkened_rects = {}
            local mock_bb = {
                darkenRect = function(self, x, y, w, h, opacity)
                    table.insert(darkened_rects, {x = x, y = y, w = w, h = h, opacity = opacity})
                end
            }

            local child_painted = false
            mock_child.paintTo = function(this, bb, x, y)
                child_painted = true
            end

            plugin:showReturnBanner(5, "Frodo", test_mentions, 20)

            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.is_not_nil(last[1])
            assert.is_not_nil(last[1].paintTo)

            last[1].paintTo(last[1], mock_bb, 0, 700)

            assert.is_true(child_painted)
            assert.are.equal(1, #darkened_rects)
            assert.are.equal(10, darkened_rects[1].x)
            assert.are.equal(20, darkened_rects[1].y)
            assert.are.equal(100, darkened_rects[1].w)
            assert.are.equal(15, darkened_rects[1].h)
            assert.are.equal(0.3, darkened_rects[1].opacity)

            package.loaded["ui/widget/buttondialog"].new = button_dialog_new
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
