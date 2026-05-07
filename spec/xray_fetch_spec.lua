-- xray_fetch_spec.lua
require("spec.spec_helper")
local fetch = require("xray_fetch")

describe("xray_fetch", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Mix in fetch methods
        for k, v in pairs(fetch) do
            plugin[k] = v
        end
        -- Mock cache manager
        plugin.cache_manager = {
            saveCache = function() return true end,
            loadCache = function() return {} end
        }
    end)

    describe("finalizeXRayData", function()
        it("merges new characters correctly in update mode", function()
            plugin.characters = {
                { name = "Alice", description = "Old description" }
            }
            local new_data = {
                characters = {
                    { name = "Alice", description = "New description" },
                    { name = "Bob", description = "A new character" }
                },
                locations = {},
                historical_figures = {},
                timeline = {}
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", true, true, 10)

            assert.are.equal(2, #plugin.characters)
            assert.are.equal("New description", plugin.characters[1].description)
            assert.are.equal("Bob", plugin.characters[2].name)
        end)

        it("filters non-narrative timeline entries", function()
            plugin.isNonNarrativeChapter = function(self, title)
                return title == "Table of Contents"
            end

            local new_data = {
                characters = {},
                locations = {},
                historical_figures = {},
                timeline = {
                    { chapter = "Chapter 1", text = "Event 1" },
                    { chapter = "Table of Contents", text = "Event 2" }
                }
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", false, true, 10)

            assert.are.equal(1, #plugin.timeline)
            assert.are.equal("Chapter 1", plugin.timeline[1].chapter)
        end)
    end)
end)
