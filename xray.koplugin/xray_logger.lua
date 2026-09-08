-- xray_logger.lua — X-Ray Plugin Logger
-- Handles log writing, rotation (max 512KB), and clearing.

local Logger = {
    path = nil,
    max_size = 512 * 1024, -- 512 KB
    _buf = {},
    _buf_count = 0,
    _buffer_limit = 20,
}

function Logger:init(path)
    self.path = path or "plugins/xray.koplugin"
    self:flush()
    
    -- Write a session start marker
    local log_path = self.path .. "/xray.log"
    pcall(function()
        local f = io.open(log_path, "a")
        if f then
            f:write("\n" .. string.rep("=", 40) .. "\n")
            f:write("--- X-Ray Session Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
            f:close()
        end
    end)
end

function Logger:flush()
    if not self._buf or #self._buf == 0 then
        self._buf = {}
        self._buf_count = 0
        return
    end

    if not self.path then
        self.path = "plugins/xray.koplugin"
    end
    local log_path = self.path .. "/xray.log"

    pcall(function()
        -- Check size and rotate if necessary
        local f_size = io.open(log_path, "r")
        if f_size then
            local current_size = f_size:seek("end")
            f_size:close()
            if current_size > self.max_size then
                os.remove(log_path .. ".old")
                os.rename(log_path, log_path .. ".old")
            end
        end

        local f = io.open(log_path, "a")
        if f then
            f:write(table.concat(self._buf, ""))
            f:close()
        end
    end)

    self._buf = {}
    self._buf_count = 0
end

function Logger:log(message)
    self._buf = self._buf or {}
    self._buf_count = (self._buf_count or 0) + 1
    table.insert(self._buf, os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message) .. "\n")

    if self._buf_count >= (self._buffer_limit or 20) then
        self:flush()
    end
end

function Logger.info(msg) Logger:log("[INFO] " .. tostring(msg)) end
function Logger.warn(msg) Logger:log("[WARN] " .. tostring(msg)) end
function Logger.err(msg) Logger:log("[ERR] " .. tostring(msg)) end

function Logger:clear()
    self._buf = {}
    self._buf_count = 0
    if not self.path then return end
    pcall(function()
        os.remove(self.path .. "/xray.log")
        os.remove(self.path .. "/xray.log.old")
    end)
end

return Logger
