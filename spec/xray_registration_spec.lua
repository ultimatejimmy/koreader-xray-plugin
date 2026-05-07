-- spec/xray_registration_spec.lua
require("spec/spec_helper")

-- Mock a minimal version of the plugin to test the registration logic
-- We don't load main.lua directly to avoid side effects of the plugin initialization.
local XRayPlugin = {}

-- Copy the logic from main.lua for testing
function XRayPlugin:_buildXRayDictButton(dict_popup_arg)
    return {
        text = "X-Ray",
        callback = function(widget_instance)
            if not self.xray_mode_enabled then return end
            local popup = widget_instance or dict_popup_arg
            local text = popup and (popup.word or popup.text or popup.selection_text)
            -- ... (rest of logic)
            return text
        end,
    }
end

function XRayPlugin:onDictButtonsReady(dict_popup, dict_buttons)
    if not self.xray_mode_enabled then return end
    if self.ui and self.ui.dictionary
            and type(self.ui.dictionary.addToDictButtons) == "function" then
        return
    end

    local btn = self:_buildXRayDictButton(dict_popup)
    local xray_button = {
        text = btn.text,
        callback = function() return btn.callback(nil) end,
    }
    table.insert(dict_buttons, { xray_button })
end

describe("X-Ray Dictionary Registration Logic", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Apply our methods to the mock plugin
        for k, v in pairs(XRayPlugin) do
            plugin[k] = v
        end
        plugin.xray_mode_enabled = true
    end)

    it("should register via the legacy hook when the new API is missing", function()
        plugin.ui.dictionary = nil -- No new API
        local dict_buttons = {}
        local dict_popup = { word = "hello" }
        
        plugin:onDictButtonsReady(dict_popup, dict_buttons)
        
        assert.are.equal(1, #dict_buttons)
        assert.are.equal("X-Ray", dict_buttons[1][1].text)
        -- Test callback
        local result = dict_buttons[1][1].callback()
        assert.are.equal("hello", result)
    end)

    it("should skip the legacy hook when the new API is present", function()
        -- Mock the new API existence
        plugin.ui.dictionary = {
            addToDictButtons = function() end
        }
        local dict_buttons = {}
        
        plugin:onDictButtonsReady({}, dict_buttons)
        
        assert.are.equal(0, #dict_buttons)
    end)

    it("should correctly handle new API callback arguments", function()
        local btn_spec = plugin:_buildXRayDictButton(nil)
        local widget_instance = { word = "world" }
        
        -- Should use the passed widget instance
        local result = btn_spec.callback(widget_instance)
        assert.are.equal("world", result)
    end)

    it("should correctly handle legacy hook upvalues", function()
        local dict_popup = { word = "upvalue" }
        local btn_spec = plugin:_buildXRayDictButton(dict_popup)
        
        -- Should use the captured upvalue when no argument is passed
        local result = btn_spec.callback(nil)
        assert.are.equal("upvalue", result)
    end)
    
    it("should respect xray_mode_enabled", function()
        plugin.xray_mode_enabled = false
        local dict_buttons = {}
        plugin:onDictButtonsReady({}, dict_buttons)
        assert.are.equal(0, #dict_buttons)
        
        plugin.xray_mode_enabled = true
        local btn_spec = plugin:_buildXRayDictButton({word="test"})
        plugin.xray_mode_enabled = false
        assert.is_nil(btn_spec.callback())
    end)
end)
