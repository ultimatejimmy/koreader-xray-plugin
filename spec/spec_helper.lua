-- spec_helper.lua
package.path = package.path .. ";xray.koplugin/?.lua"

-- Mocking KOReader environment
package.loaded["device"] = {
    getModel = function() return "K5" end,
    isKindle = function() return true end,
    isPocketBook = function() return false end,
    isKobo = function() return false end,
    isKoboV2 = function() return false end
}

package.loaded["docsettings"] = {
    getSidecarDir = function(_, book_path) return book_path .. ".sdr" end
}

package.loaded["lfs"] = {
    attributes = function(path) 
        -- Basic mock: if it ends in .sdr, it's a directory
        if path:match("%.sdr$") or path:match("%.sdr/$") then
            return { mode = "directory" }
        end
        -- If we can open it, it's a file
        local f = io.open(path, "r")
        if f then
            f:close()
            return { mode = "file" }
        end
        return nil
    end,
    mkdir = function() return true end
}

package.loaded["logger"] = {
    info = function(...) end,
    warn = function(...) end,
    err = function(...) end,
    debug = function(...) end
}

package.loaded["xray_aihelper"] = {
    log = function(...) end,
    getProvider = function() return "openai" end
}

package.loaded["datastorage"] = {
    getSettingsDir = function() return "/tmp/koreader/settings" end
}

package.loaded["ui/uimanager"] = {
    show = function() end,
    close = function() end,
    scheduleIn = function() end
}
package.loaded["ui/widget/infomessage"] = {}
package.loaded["ui/widget/buttondialog"] = {
    new = function() return {} end
}
package.loaded["ui/network/manager"] = {
    runWhenOnline = function(cb) cb() end
}

function _G.createMockPlugin()
    local plugin = {
        ui = {
            document = {
                file = "test_book.epub",
                getToc = function() return {} end,
                getProps = function() return { title = "Test Title", authors = "Test Author" } end
            },
            getCurrentPage = function() return 10 end
        },
        loc = {
            t = function(s) return s end
        },
        ai_helper = {
            log = function() end,
            settings = {}
        },
        characters = {},
        locations = {},
        timeline = {},
        historical_figures = {},
        log = function(...) end,
        normalizeChapterName = function(self, name) return name:lower() end,
        isNonNarrativeChapter = function() return false end,
        deduplicateByName = function(self, list) return list end,
        sortDataByFrequency = function(self, list) return list end,
        assignTimelinePages = function() end,
        sortTimelineByTOC = function() end
    }
    return plugin
end
