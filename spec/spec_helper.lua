-- spec_helper.lua
package.path = package.path .. ";xray.koplugin/?.lua"
package.path = package.path .. ";/home/jpautz/.luarocks/share/lua/5.1/?.lua"
package.path = package.path .. ";/home/jpautz/.luarocks/share/lua/5.1/?/init.lua"

-- Mocking KOReader environment
package.loaded["device"] = {
    getModel = function() return "K5" end,
    isKindle = function() return true end,
    isPocketBook = function() return false end,
    isKobo = function() return false end,
    isKoboV2 = function() return false end,
    screen = {
        getWidth = function() return 600 end,
        getHeight = function() return 800 end
    }
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

package.loaded["xray_logger"] = {
    log = function(...) end,
}

package.loaded["datastorage"] = {
    getSettingsDir = function() return "/tmp/koreader/settings" end
}

-- UI tracking for testing
_G.ui_tracker = {
    shown = {},
    last_shown = nil,
    closed = {}
}

package.loaded["ui/uimanager"] = {
    show = function(a, b)
        local w = b or a
        table.insert(_G.ui_tracker.shown, w)
        _G.ui_tracker.last_shown = w
    end,
    close = function(a, b)
        local w = b or a
        table.insert(_G.ui_tracker.closed, w)
    end,
    scheduleIn = function(a, b)
        if type(a) == "function" then a()
        elseif type(b) == "function" then b() end
    end,
    nextTick = function(f) f() end,
    setDirty = function() end
}
package.loaded["ui/widget/infomessage"] = {
    new = function(a, b) return { type = "InfoMessage", args = b or a } end
}
package.loaded["ui/widget/buttondialog"] = {
    new = function(a, b) return { type = "ButtonDialog", args = b or a } end
}
package.loaded["ui/widget/confirmbox"] = {
    new = function(a, b) return { type = "ConfirmBox", args = b or a } end
}
package.loaded["ui/widget/menu"] = {
    new = function(a, b) return { type = "Menu", args = b or a } end
}
package.loaded["gettext"] = {
    _ = function(s) return s end,
    getLanguage = function() return "en" end
}
package.loaded["ui/trapper"] = {
    dismissableRunInSubprocess = function(_, _, f) return true, f() end
}
package.loaded["xray_logger"] = {
    log = function(...) end,
}
package.loaded["socket.http"] = {}
package.loaded["ssl.https"] = {}
package.loaded["ltn12"] = {}
package.loaded["socket"] = {}
package.loaded["socketutil"] = {}
local json_lib = nil
pcall(function() json_lib = require("dkjson") end)
if not json_lib then
    json_lib = {
        encode = function(t) return "{}" end,
        decode = function(s) return {} end
    }
end
package.loaded["json"] = json_lib

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
            t = function(s, s2) return s2 or s end,
            getLanguage = function() return "en" end,
            setLanguage = function() end
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
