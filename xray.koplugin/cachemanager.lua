-- CacheManager - X-Ray data caching system
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local DocSettings = require("docsettings")
local AIHelper = require("aihelper")

local CacheManager = {}

function CacheManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Get cache file path for a book
function CacheManager:getCachePath(book_path)
    if not book_path then
        return nil
    end
    
    -- Use KOReader's sidecar directory
    local cache_dir = DocSettings:getSidecarDir(book_path)
    local cache_file = cache_dir .. "/xray_cache.lua"
    
    logger.info("CacheManager: Cache path:", cache_file)
    AIHelper:log("CacheManager: Cache path: " .. tostring(cache_file))
    return cache_file
end

-- Ensure directory exists
function CacheManager:ensureDirectory(path)
    local dir = path:match("(.+)/[^/]+$")
    if not dir then
        return false
    end
    
    local attr = lfs.attributes(dir)
    if attr and attr.mode == "directory" then
        return true
    end
    
    logger.info("CacheManager: Creating directory:", dir)
    local success, err = lfs.mkdir(dir)
    
    if not success then
        logger.warn("CacheManager: Failed to create directory:", err or "unknown error")
        return false
    end
    
    return true
end

-- Save book data to cache
function CacheManager:saveCache(book_path, data)
    if not book_path or not data then
        logger.warn("CacheManager: Cannot save cache - invalid parameters")
        return false
    end
    
    local cache_file = self:getCachePath(book_path)
    if not cache_file then
        logger.warn("CacheManager: Cannot determine cache path")
        return false
    end
    
    -- Ensure directory exists
    if not self:ensureDirectory(cache_file) then
        logger.warn("CacheManager: Cannot create cache directory")
        return false
    end
    
    -- Add timestamp
    data.cached_at = os.time()
    data.cache_version = "6.0"
    
    -- Serialize data
    local success, err = pcall(function()
        local f, open_err = io.open(cache_file, "w")
        
        if not f then
            logger.warn("CacheManager: Cannot open file for writing:", cache_file)
            logger.warn("CacheManager: Error:", open_err or "unknown")
            return false
        end
        
        local serialized_data = self:serialize(data)
        
        if not serialized_data then
            logger.warn("CacheManager: Failed to serialize data")
            f:close()
            return false
        end
        
        f:write("-- X-Ray Cache v6.0\n")
        f:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:write("return " .. serialized_data)
        f:close()
        
        logger.info("CacheManager: Saved cache to:", cache_file)
        AIHelper:log("CacheManager: Saved cache to: " .. tostring(cache_file))
        return true
    end)
    
    if not success then
        logger.warn("CacheManager: Failed to save cache:", err or "unknown error")
        AIHelper:log("CacheManager: Failed to save cache: " .. tostring(err or "unknown error"))
        return false
    end
    
    return success
end

-- Load book data from cache
function CacheManager:loadCache(book_path)
    if not book_path then
        return nil
    end
    
    local cache_file = self:getCachePath(book_path)
    if not cache_file then
        logger.warn("CacheManager: Cannot determine cache path")
        AIHelper:log("CacheManager: Cannot determine cache path")
        return nil
    end
    
    -- Check if cache file exists
    local attr = lfs.attributes(cache_file)
    if not attr then
        logger.info("CacheManager: No cache file found")
        AIHelper:log("CacheManager: No cache file found for " .. tostring(book_path))
        return nil
    end
    
    -- Load cache
    local success, data = pcall(function()
        return dofile(cache_file)
    end)
    
    if not success or not data then
        logger.warn("CacheManager: Failed to load cache:", data or "unknown error")
        AIHelper:log("CacheManager: Failed to load cache: " .. tostring(data or "unknown error"))
        return nil
    end
    
    -- Check cache version
    if data.cache_version ~= "6.0" then
        logger.warn("CacheManager: Cache version mismatch, ignoring")
        AIHelper:log("CacheManager: Cache version mismatch (found " .. tostring(data.cache_version) .. ", expected 6.0)")
        return nil
    end
    
    -- Cache age check removed - cache is now permanent
    -- Cache will stay valid forever unless manually cleared
    
    logger.info("CacheManager: Loaded cache from:", cache_file)
    AIHelper:log("CacheManager: Loaded cache from " .. tostring(cache_file))
    if data.cached_at then
        local cache_age_days = math.floor((os.time() - data.cached_at) / 86400)
        logger.info("CacheManager: Cache age:", cache_age_days, "days (no expiration)")
        AIHelper:log("CacheManager: Cache age: " .. tostring(cache_age_days) .. " days")
    end
    
    return data
end

-- Serialize Lua table to string (with better error handling)
function CacheManager:serialize(obj, indent, seen)
    indent = indent or ""
    seen = seen or {}
    
    local t = type(obj)
    
    if t == "table" then
        -- Prevent infinite recursion
        if seen[obj] then
            return "{--[[circular reference]]}"
        end
        seen[obj] = true
        
        local s = "{\n"
        for k, v in pairs(obj) do
            -- Skip functions and userdata
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
                s = s .. indent .. "  "
                if type(k) == "string" then
                    -- Check if key needs escaping
                    if k:match("^[%a_][%w_]*$") then
                        s = s .. k .. " = "
                    else
                        s = s .. "[" .. string.format("%q", k) .. "] = "
                    end
                else
                    s = s .. "[" .. tostring(k) .. "] = "
                end
                s = s .. self:serialize(v, indent .. "  ", seen) .. ",\n"
            end
        end
        s = s .. indent .. "}"
        return s
    elseif t == "string" then
        return string.format("%q", obj)
    elseif t == "number" or t == "boolean" then
        return tostring(obj)
    elseif t == "nil" then
        return "nil"
    else
        -- Skip functions, userdata, threads
        return "nil"
    end
end

-- Clear cache for a book
function CacheManager:clearCache(book_path)
    local cache_file = self:getCachePath(book_path)
    if cache_file then
        local success, err = os.remove(cache_file)
        if success then
            logger.info("CacheManager: Cleared cache:", cache_file)
            return true
        else
            logger.warn("CacheManager: Failed to clear cache:", err or "unknown")
            return false
        end
    end
    return false
end

return CacheManager