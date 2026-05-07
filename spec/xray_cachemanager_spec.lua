-- xray_cachemanager_spec.lua
require("spec.spec_helper")
local cache_manager = require("xray_cachemanager"):new()

describe("xray_cachemanager", function()
    local test_book = "/tmp/test_book.epub"
    local test_cache = test_book .. ".sdr/xray_cache.lua"

    before_each(function()
        -- Ensure clean state
        os.execute("rm -rf /tmp/test_book.epub.sdr")
        os.execute("mkdir -p /tmp/test_book.epub.sdr")
    end)

    describe("getCachePath", function()
        it("returns correct sidecar path", function()
            local path = cache_manager:getCachePath(test_book)
            assert.are.equal(test_cache, path)
        end)
    end)

    describe("Serialization and Saving", function()
        it("saves and loads data correctly", function()
            local data = {
                characters = {
                    { name = "Alice", role = "Protagonist" }
                },
                last_fetch_page = 42
            }

            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Alice", loaded.characters[1].name)
            assert.are.equal(42, loaded.last_fetch_page)
            assert.are.equal("6.0", loaded.cache_version)
        end)

        it("handles circular references gracefully", function()
            local data = { name = "Alice" }
            data.self = data -- Circular reference

            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local loaded = cache_manager:loadCache(test_book)
            -- The circular reference is serialized as an empty table with a comment marker
            assert.is_table(loaded.self)
            assert.are.equal(0, #loaded.self)
        end)
    end)
end)
