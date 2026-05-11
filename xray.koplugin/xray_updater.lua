-- updater.lua — X-Ray Plugin OTA Updater
-- Adapted from Simple UI OTA Updater
-- Checks GitHub Releases for a newer version, informs the user,
-- and prompts to download and install.

local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox  = require("ui/widget/confirmbox")
local logger      = require("logger")

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local GITHUB_OWNER = "ultimatejimmy"
local GITHUB_REPO  = "koreader-xray-plugin"
local ASSET_NAME   = "xray.koplugin.zip"

-- Cache validity time in seconds. 0 = disable cache.
local CACHE_TTL    = 3600  -- 1 hour

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

local M = {}

-- Store a reference to the localization object
M.loc = nil

-- Plugin directory (resolved from this file's path)
local _plugin_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$")
    or "/mnt/us/extensions/xray.koplugin"

local function _apiUrl(use_beta)
    if use_beta then
        return string.format(
            "https://api.github.com/repos/%s/%s/releases",
            GITHUB_OWNER, GITHUB_REPO
        )
    end
    return string.format(
        "https://api.github.com/repos/%s/%s/releases/latest",
        GITHUB_OWNER, GITHUB_REPO
    )
end

-- Helper to safely call localizer
local function t(key, ...)
    if M.loc and M.loc.t then
        return M.loc:t(key, ...)
    end
    -- Fallback if loc is missing
    return key
end

local function _cacheFile(use_beta)
    local suffix = use_beta and "_beta" or ""
    local ok, DS = pcall(require, "datastorage")
    if ok and DS then
        return DS:getSettingsDir() .. "/xray_update_cache" .. suffix .. ".json"
    end
    return "/tmp/xray_update_cache" .. suffix .. ".json"
end

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

local function _loadCache(use_beta)
    if CACHE_TTL <= 0 then return nil end
    local path = _cacheFile(use_beta)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local raw = fh:read("*a")
    fh:close()
    local ok_j, json = pcall(require, "json")
    if not ok_j then return nil end
    local ok_d, data = pcall(json.decode, raw)
    if not ok_d or type(data) ~= "table" then return nil end
    if (os.time() - (data.timestamp or 0)) > CACHE_TTL then return nil end
    return data.payload
end

local function _saveCache(payload, use_beta)
    if CACHE_TTL <= 0 then return end
    local ok_j, json = pcall(require, "json")
    if not ok_j then return end
    local ok_e, encoded = pcall(json.encode, { timestamp = os.time(), payload = payload })
    if not ok_e then return end
    local fh = io.open(_cacheFile(use_beta), "w")
    if fh then
        fh:write(encoded)
        fh:close()
    end
end

local function _clearCache(use_beta)
    pcall(os.remove, _cacheFile(use_beta))
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _currentVersion()
    local meta_path = _plugin_dir .. "/_meta.lua"
    local ok, meta = pcall(dofile, meta_path)
    if ok and type(meta) == "table" and meta.version then
        return meta.version
    end
    return "0.0.0"
end

local function _versionLessThan(a, b)
    local function parts(v)
        local t_parts = {}
        if not v then return t_parts end
        for n in v:gmatch("(%d+)") do
            t_parts[#t_parts + 1] = tonumber(n)
        end
        return t_parts
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local va = pa[i] or 0
        local vb = pb[i] or 0
        if va < vb then return true end
        if va > vb then return false end
    end
    return false
end

local function _toast(msg, timeout)
    local w = InfoMessage:new{ text = msg, timeout = timeout or 4 }
    UIManager:show(w)
    return w
end

local function _closeWidget(w)
    if w then UIManager:close(w) end
end

-- ---------------------------------------------------------------------------
-- HTTP with socketutil
-- ---------------------------------------------------------------------------

local function _httpGet(url)
    local ok_su, socketutil = pcall(require, "socketutil")
    local http   = require("socket/http")
    local ltn12  = require("ltn12")
    local socket = require("socket")

    if ok_su then
        socketutil:set_timeout(
            socketutil.LARGE_BLOCK_TIMEOUT,
            socketutil.LARGE_TOTAL_TIMEOUT
        )
    end

    local chunks = {}
    local code, headers, status = socket.skip(1, http.request({
        url      = url,
        method   = "GET",
        headers  = {
            ["User-Agent"] = "KOReader-XRay-Updater/1.0",
            ["Accept"]     = "application/vnd.github.v3+json",
        },
        sink     = ltn12.sink.table(chunks),
        redirect = true,
    }))

    if ok_su then socketutil:reset_timeout() end

    if ok_su and (
        code == socketutil.TIMEOUT_CODE or
        code == socketutil.SSL_HANDSHAKE_CODE or
        code == socketutil.SINK_TIMEOUT_CODE
    ) then
        return nil, "timeout (" .. tostring(code) .. ")"
    end

    if headers == nil then
        return nil, "network error (" .. tostring(code or status) .. ")"
    end

    if code == 200 then
        return table.concat(chunks)
    end
    return nil, string.format("HTTP %s", tostring(code))
end

local function _httpGetToFile(url, dest_path)
    local ok_su, socketutil = pcall(require, "socketutil")
    local http   = require("socket/http")
    local ltn12  = require("ltn12")
    local socket = require("socket")

    local fh, err_open = io.open(dest_path, "wb")
    if not fh then
        return nil, "Could not create file: " .. tostring(err_open)
    end

    if ok_su then
        socketutil:set_timeout(
            socketutil.FILE_BLOCK_TIMEOUT,
            socketutil.FILE_TOTAL_TIMEOUT
        )
    end

    local code, headers, status = socket.skip(1, http.request({
        url      = url,
        method   = "GET",
        headers  = { ["User-Agent"] = "KOReader-XRay-Updater/1.0" },
        sink     = ltn12.sink.file(fh),
        redirect = true,
    }))

    if ok_su then socketutil:reset_timeout() end

    if ok_su and (
        code == socketutil.TIMEOUT_CODE or
        code == socketutil.SSL_HANDSHAKE_CODE or
        code == socketutil.SINK_TIMEOUT_CODE
    ) then
        pcall(os.remove, dest_path)
        return nil, "timeout (" .. tostring(code) .. ")"
    end

    if headers == nil then
        pcall(os.remove, dest_path)
        return nil, "network error (" .. tostring(code or status) .. ")"
    end

    if code == 200 then return true end
    pcall(os.remove, dest_path)
    return nil, string.format("HTTP %s", tostring(code))
end

-- ---------------------------------------------------------------------------
-- JSON parsing
-- ---------------------------------------------------------------------------

local function _parseRelease(body, use_beta)
    local ok_j, json = pcall(require, "json")

    if not ok_j then
        logger.warn("xray updater: json module not available, using fallback regex")
        local function jsonStr(key)
            return body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
        end
        local tag = jsonStr("tag_name")
        if not tag then return nil, "could not parse tag_name" end
        local download_url = body:match(
            '"browser_download_url"%s*:%s*"([^"]*'
            .. ASSET_NAME:gsub("%.", "%%.") .. '[^"]*)"'
        )
        local notes = body:match('"body"%s*:%s*"(.-)"[,}]')
        if notes then
            notes = notes:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\\\", "\\")
        end
        return {
            version      = tag:match("v?(.*)"),
            download_url = download_url,
            notes        = (notes and notes ~= "") and notes or nil,
        }
    end

    local ok_d, data = pcall(json.decode, body)
    if not ok_d or type(data) ~= "table" then
        return nil, "JSON parse error: " .. tostring(data)
    end

    -- GitHub error messages usually have a 'message' field
    if data.message and not data.tag_name and not (use_beta and data[1]) then
        return nil, "GitHub API error: " .. tostring(data.message)
    end

    -- If we query /releases instead of /releases/latest, we get an array
    local release_data = data
    if use_beta then
        if type(data) == "table" and data[1] then
            release_data = data[1]
        elseif type(data) == "table" and #data == 0 then
            return nil, "No releases found in repository"
        else
            return nil, "Unexpected API response format (expected array)"
        end
    end

    local tag = release_data.tag_name
    if not tag then return nil, "tag_name missing from API response" end

    local download_url = nil
    for _, asset in ipairs(release_data.assets or {}) do
        if type(asset.name) == "string" and asset.name == ASSET_NAME then
            download_url = asset.browser_download_url
            break
        end
    end

    local notes = release_data.body
    if notes and notes ~= "" then
        notes = notes:gsub("#+%s*", "")
        notes = notes:gsub("%*%*(.-)%*%*", "%1")
        notes = notes:gsub("`(.-)`", "%1")
        notes = notes:gsub("\r\n", "\n"):gsub("\r", "\n")
        if #notes > 600 then notes = notes:sub(1, 597) .. "..." end
        notes = notes:match("^%s*(.-)%s*$")
    end

    return {
        version      = tag:match("v?(.*)"),
        download_url = download_url,
        notes        = (notes and notes ~= "") and notes or nil,
        html_url     = release_data.html_url,
    }
end

-- ---------------------------------------------------------------------------
-- Unzip
-- ---------------------------------------------------------------------------

local function _unzip(zip_path, dest_dir)
    local cmd = string.format("unzip -o -q %q -d %q", zip_path, dest_dir)
    local ret = os.execute(cmd)
    if ret ~= 0 and ret ~= true then
        return nil, "unzip failed (exit " .. tostring(ret) .. ")"
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Download & Install
-- ---------------------------------------------------------------------------

local function _tmpZipPath()
    local ok, DS = pcall(require, "datastorage")
    if ok and DS then
        return DS:getSettingsDir() .. "/xray_update.zip"
    end
    local probe = "/tmp/.xray_probe"
    local fh = io.open(probe, "w")
    if fh then fh:close(); os.remove(probe); return "/tmp/xray_update.zip" end
    return _plugin_dir .. "/xray_update.zip"
end

local function _applyUpdate(download_url, new_version)
    local tmp_zip    = _tmpZipPath()
    local parent_dir = _plugin_dir:match("^(.+)/[^/]+$") or _plugin_dir

    local progress_msg = _toast(
        t("updater_downloading", new_version), 120
    )

    local ok_tr, Trapper = pcall(require, "ui/trapper")

    local function doDownloadAndInstall()
        local config_path = _plugin_dir .. "/xray_config.lua"
        local saved_keys = {}
        local ok, cfg = pcall(dofile, config_path)
        if ok and type(cfg) == "table" then
            saved_keys.gemini = cfg.gemini_api_key
            saved_keys.chatgpt = cfg.chatgpt_api_key
            saved_keys.deepseek = cfg.deepseek_api_key
            saved_keys.claude = cfg.claude_api_key
            saved_keys.custom1_key = cfg.custom1_api_key
            saved_keys.custom1_endpoint = cfg.custom1_endpoint
            saved_keys.custom1_model = cfg.custom1_model
            saved_keys.custom2_key = cfg.custom2_api_key
            saved_keys.custom2_endpoint = cfg.custom2_endpoint
            saved_keys.custom2_model = cfg.custom2_model
        end

        -- 2. Download the update
        local dl_ok, dl_err = _httpGetToFile(download_url, tmp_zip)
        if not dl_ok then
            return { success = false, stage = "download", err = dl_err }
        end

        -- 3. Extract (overwrites xray_config.lua with the default one)
        local uz_ok, uz_err = _unzip(tmp_zip, parent_dir)
        os.remove(tmp_zip)
        if not uz_ok then
            return { success = false, stage = "unzip", err = uz_err }
        end

        -- 4. Smart Merge: Inject keys back into the NEW config file
        if (saved_keys.gemini and saved_keys.gemini ~= "") or
           (saved_keys.chatgpt and saved_keys.chatgpt ~= "") or
           (saved_keys.deepseek and saved_keys.deepseek ~= "") or
           (saved_keys.claude and saved_keys.claude ~= "") or
           (saved_keys.custom1_key and saved_keys.custom1_key ~= "") or
           (saved_keys.custom2_key and saved_keys.custom2_key ~= "") then
            local nfh = io.open(config_path, "r")
            if nfh then
                local content = nfh:read("*a")
                nfh:close()

                -- Replace empty key placeholders with the saved user keys
                if saved_keys.gemini and saved_keys.gemini ~= "" then
                    content = content:gsub('gemini_api_key%s*=%s*""', 'gemini_api_key = "' .. saved_keys.gemini .. '"')
                end
                if saved_keys.chatgpt and saved_keys.chatgpt ~= "" then
                    content = content:gsub('chatgpt_api_key%s*=%s*""', 'chatgpt_api_key = "' .. saved_keys.chatgpt .. '"')
                end
                if saved_keys.deepseek and saved_keys.deepseek ~= "" then
                    content = content:gsub('deepseek_api_key%s*=%s*""', 'deepseek_api_key = "' .. saved_keys.deepseek .. '"')
                end
                if saved_keys.claude and saved_keys.claude ~= "" then
                    content = content:gsub('claude_api_key%s*=%s*""', 'claude_api_key = "' .. saved_keys.claude .. '"')
                end
                
                if saved_keys.custom1_key and saved_keys.custom1_key ~= "" then
                    content = content:gsub('custom1_api_key%s*=%s*""', 'custom1_api_key = "' .. saved_keys.custom1_key .. '"')
                end
                if saved_keys.custom1_endpoint and saved_keys.custom1_endpoint ~= "" then
                    content = content:gsub('custom1_endpoint%s*=%s*""', 'custom1_endpoint = "' .. saved_keys.custom1_endpoint .. '"')
                end
                if saved_keys.custom1_model and saved_keys.custom1_model ~= "" then
                    content = content:gsub('custom1_model%s*=%s*""', 'custom1_model = "' .. saved_keys.custom1_model .. '"')
                end
                
                if saved_keys.custom2_key and saved_keys.custom2_key ~= "" then
                    content = content:gsub('custom2_api_key%s*=%s*""', 'custom2_api_key = "' .. saved_keys.custom2_key .. '"')
                end
                if saved_keys.custom2_endpoint and saved_keys.custom2_endpoint ~= "" then
                    content = content:gsub('custom2_endpoint%s*=%s*""', 'custom2_endpoint = "' .. saved_keys.custom2_endpoint .. '"')
                end
                if saved_keys.custom2_model and saved_keys.custom2_model ~= "" then
                    content = content:gsub('custom2_model%s*=%s*""', 'custom2_model = "' .. saved_keys.custom2_model .. '"')
                end

                local outh = io.open(config_path, "w")
                if outh then
                    outh:write(content)
                    outh:close()
                end
            end
        end

        return { success = true }
    end

    local function handleInstallResult(result)
        _closeWidget(progress_msg)
        if not result or not result.success then
            local stage = result and result.stage or "unknown"
            local err   = result and result.err   or "unknown error"
            logger.err("xray updater: failed at", stage, "-", err)
            if stage == "download" then
                _toast(t("updater_err_download", tostring(err)))
            else
                _toast(t("updater_err_extract", tostring(err)))
            end
            return
        end
        _clearCache(true)
        _clearCache(false)
        UIManager:show(ConfirmBox:new{
            text = t("updater_success_restart", new_version),
            ok_text     = t("updater_btn_restart"),
            cancel_text = t("updater_btn_later"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end

    if ok_tr and Trapper and Trapper.dismissableRunInSubprocess then
        local completed, result = Trapper:dismissableRunInSubprocess(
            doDownloadAndInstall,
            progress_msg,
            function(res) handleInstallResult(res) end
        )
        if completed and result then
            UIManager:scheduleIn(0.2, function() handleInstallResult(result) end)
        elseif completed == false then
            _closeWidget(progress_msg)
            pcall(os.remove, tmp_zip)
            _toast(t("updater_cancelled_update"))
        end
    else
        UIManager:scheduleIn(0.3, function()
            handleInstallResult(doDownloadAndInstall())
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Version Check
-- ---------------------------------------------------------------------------

local function _showUpdateDialog(release, current)
    local latest       = release.version
    local download_url = release.download_url
    local notes        = release.notes

    if not _versionLessThan(current, latest) then
        logger.info("xray updater: up to date (" .. current .. ")")
        _toast(t("updater_up_to_date", current))
        return
    end

    logger.info("xray updater: new version available:", latest)

    local header = t("updater_available_header", latest, current)
    local footer = t("updater_download_prompt")
    local notes_block = notes
        and ("\n\n" .. t("updater_whats_new") .. "\n" .. notes)
        or  ""

    if not download_url then
        UIManager:show(ConfirmBox:new{
            text        = header .. notes_block .. "\n\n" .. t("updater_no_asset"),
            ok_text     = t("updater_btn_open_browser"),
            cancel_text = t("updater_btn_cancel"),
            ok_callback = function()
                local Device = require("device")
                if Device:canOpenLink() then
                    Device:openLink(string.format(
                        "https://github.com/%s/%s/releases/latest",
                        GITHUB_OWNER, GITHUB_REPO
                    ))
                end
            end,
        })
        return
    end

    UIManager:show(ConfirmBox:new{
        text        = header .. notes_block .. footer,
        ok_text     = t("updater_btn_download"),
        cancel_text = t("updater_btn_cancel"),
        ok_callback = function() _applyUpdate(download_url, latest) end,
    })
end

local function _doFetch(use_beta)
    local cached = _loadCache(use_beta)
    if cached then
        logger.info("xray updater: using cache (" .. (use_beta and "beta" or "stable") .. ")")
        return cached
    end
    local body, err = _httpGet(_apiUrl(use_beta))
    if not body then return { error = err } end
    local release, parse_err = _parseRelease(body, use_beta)
    if not release then return { error = "parse error: " .. tostring(parse_err) } end
    _saveCache(release, use_beta)
    return release
end

function M._doCheckForUpdates(current, use_beta)
    local checking_msg = _toast(t("updater_checking"), 15)
    local ok_tr, Trapper = pcall(require, "ui/trapper")

    local function handleCheckResult(release)
        _closeWidget(checking_msg)
        if not release then
            _toast(t("updater_error_checking"))
            return
        end
        if release.error then
            logger.err("xray updater: check error:", release.error)
            _toast(t("updater_error_checking_detail", tostring(release.error)))
            return
        end
        _showUpdateDialog(release, current)
    end

    if ok_tr and Trapper and Trapper.dismissableRunInSubprocess then
        local completed, result = Trapper:dismissableRunInSubprocess(
            function() return _doFetch(use_beta) end,
            checking_msg,
            function(res) handleCheckResult(res) end
        )
        if completed and result then
            UIManager:scheduleIn(0.2, function() handleCheckResult(result) end)
        elseif completed == false then
            _closeWidget(checking_msg)
            _toast(t("updater_cancelled_check"))
        end
    else
        UIManager:scheduleIn(0.3, function()
            handleCheckResult(_doFetch(use_beta))
        end)
    end
end

-- localization param allows the caller to pass the X-Ray loc module
function M.checkForUpdates(loc, use_beta)
    M.loc = loc
    local current = _currentVersion()
    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_nm and NetworkMgr and NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(function()
            M._doCheckForUpdates(current, use_beta)
        end)
        return
    end
    M._doCheckForUpdates(current, use_beta)
end

function M.checkSilentForUpdates(loc, use_beta)
    M.loc = loc
    local current = _currentVersion()
    local release = _doFetch(use_beta)
    
    if release and not release.error then
        if _versionLessThan(current, release.version) then
            _showUpdateDialog(release, current)
        end
    end
end

return M
