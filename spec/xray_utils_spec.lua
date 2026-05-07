-- xray_utils_spec.lua
require("spec.spec_helper")
local utils = require("xray_utils")
local device = require("device")

describe("xray_utils", function()
    it("identifies PW1 (K5) as a low power device", function()
        device.isKindle = function() return true end
        device.getModel = function() return "K5" end
        assert.is_true(utils:isLowPowerDevice())
    end)

    it("identifies modern devices as not low power", function()
        device.isKindle = function() return true end
        device.getModel = function() return "K11" end -- Newer Kindle
        assert.is_false(utils:isLowPowerDevice())
    end)

    it("identifies older Kobo devices as low power", function()
        device.isKindle = function() return false end
        device.isKobo = function() return true end
        device.isKoboV2 = function() return false end
        assert.is_true(utils:isLowPowerDevice())
    end)
end)
