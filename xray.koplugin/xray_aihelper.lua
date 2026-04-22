-- AIHelper - Google Gemini & ChatGPT for X-Ray
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local XRayLogger = require("xray_logger")
local Trapper = require("ui/trapper")

-- Optimization: Use rapidjson if available
local rapidjson_ok, rapidjson = pcall(require, "rapidjson")
local json = rapidjson_ok and rapidjson or require("json")

local AIHelper = {
    path = nil,
    providers = {
        gemini = {
            name = "Google Gemini",
            enabled = true,
            api_key = nil,
        },
        chatgpt = {
            name = "ChatGPT",
            enabled = true,
            api_key = nil,
            endpoint = "https://api.openai.com/v1/chat/completions",
        }
    },
    default_provider = nil,
    current_language = "en",
    prompts = nil,
    trap_widget = nil,
}

-- Custom logger for X-Ray
function AIHelper:log(message)
    XRayLogger:log(message)
end

function AIHelper:setTrapWidget(trap_widget) self.trap_widget = trap_widget end
function AIHelper:resetTrapWidget() self.trap_widget = nil end

function AIHelper:makeRequest(url, headers, request_body, timeout, maxtime)
    timeout = timeout or 300; maxtime = maxtime or 900
    local function performRequest()
        local http_req = require("socket.http"); local https_req = require("ssl.https")
        local ltn12_req = require("ltn12"); local socketutil_req = require("socketutil")
        https_req.cert_verify = false; socketutil_req:set_timeout(timeout, maxtime)
        local response_body = {}
        local request = { url = url, method = "POST", headers = headers or {}, source = ltn12_req.source.string(request_body or ""), sink = socketutil_req.table_sink(response_body) }
        local ok, code, response_headers, status
        local pcall_ok, pcall_err = pcall(function() ok, code, response_headers, status = http_req.request(request) end)
        if not pcall_ok then return nil, "error_crash", tostring(pcall_err) end
        socketutil_req:reset_timeout()
        local response_text = table.concat(response_body)
        if response_headers and response_headers["content-length"] then
            local clen = tonumber(response_headers["content-length"])
            if clen and #response_text < clen then return nil, "error_incomplete", "Incomplete response" end
        end
        if ok == nil and (code == "timeout" or tostring(code):find("timeout")) then return nil, "error_timeout", "Connection timed out" end
        return ok, code, response_text, status
    end
    
    if self.trap_widget then
        local completed, ok, code, response_text, status = Trapper:dismissableRunInSubprocess(performRequest, self.trap_widget)
        if not completed then return nil, "USER_CANCELLED", "Request cancelled" end
        -- Note: Subprocess results can sometimes be nil if not handled perfectly, fallback to sync if needed
        if ok == nil and code == nil then return performRequest() end
        return ok, code, response_text, status
    else
        return performRequest()
    end
end

-- Build all possible HTTP request parameters (primary and fallback) for a comprehensive fetch.
-- Returns: { {url, headers, body, provider, model}, ... } or nil, error_code, error_msg
function AIHelper:buildComprehensiveRequest(title, author, context)
    local prompt = self:createPrompt(title, author, context, "comprehensive_xray")
    local primary = self.settings.primary_ai or { provider = "gemini", model = "gemini-2.5-flash" }
    local secondary = self.settings.secondary_ai or { provider = "gemini", model = "gemini-2.5-flash-lite" }

    local requests = {}
    for _, ai in ipairs({ primary, secondary }) do
        local config = self.providers[ai.provider]
        if config and config.api_key and config.api_key ~= "" then
            local url, headers, body
            if ai.provider == "gemini" then
                local model = ai.model or "gemini-2.5-flash"
                local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
                url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
                headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = config.api_key }
                body = json.encode({
                    contents = {{ role = "user", parts = {{ text = prompt }} }},
                    system_instruction = { parts = {{ text = system_instruction_text }} },
                    safetySettings = {
                        { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
                    },
                    generationConfig = { temperature = 0.2, maxOutputTokens = 16384 }
                })
            else
                local model = ai.model or "gpt-4o-mini"
                url = config.endpoint or "https://api.openai.com/v1/chat/completions"
                headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.api_key }
                body = json.encode({ 
                    model = model, 
                    messages = {{ role = "user", content = prompt }}, 
                    response_format = { type = "json_object" },
                    max_tokens = 4096
                })
            end
            table.insert(requests, { url = url, headers = headers, body = body, provider = ai.provider, model = ai.model })
        end
    end
    
    if #requests > 0 then
        return requests
    end
    return nil, "error_api", "No API key configured"
end

-- Check if at least one API key is configured
function AIHelper:hasApiKey()
    if self.providers.gemini and self.providers.gemini.api_key and self.providers.gemini.api_key ~= "" then return true end
    if self.providers.chatgpt and self.providers.chatgpt.api_key and self.providers.chatgpt.api_key ~= "" then return true end
    return false
end

-- Fork a child process to perform the HTTP request. Returns true if started.
function AIHelper:makeRequestAsync(request_params, result_file)
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if not ok_ffi then
        ok_ffi, ffiutil = pcall(require, "ffiutil")
    end
    
    local function child_logic(pid, write_fd)
        local child_ok, child_err = pcall(function()
            self:log("AIHelper Child: Started background process")
            local http_req = require("socket.http")
            local https_req = require("ssl.https")
            local ltn12_req = require("ltn12")
            local socketutil_req = require("socketutil")
            https_req.cert_verify = false
            socketutil_req:set_timeout(60, 120)  -- shorter timeout for background

            local requests = request_params
            if request_params.url then requests = { request_params } end -- Handle single request fallback

            local success_found = false
            for i, req in ipairs(requests) do
                self:log(string.format("AIHelper Child: Sending request %d/%d to %s (%s)", i, #requests, req.provider, req.model or "default"))
                local response_body = {}
                local request = {
                    url = req.url,
                    method = "POST",
                    headers = req.headers or {},
                    source = ltn12_req.source.string(req.body or ""),
                    sink = socketutil_req.table_sink(response_body)
                }
                local ok, code, response_headers, status = http_req.request(request)
                local response_text = table.concat(response_body)
                local code_num = tonumber(code)

                self:log("AIHelper Child: Request finished with code " .. tostring(code))

                if code_num == 200 then
                    -- Quick JSON validation before accepting the response
                    local json_req = require("json")
                    local valid_json = false
                    local parse_ok, parsed = pcall(json_req.decode, response_text)
                    if parse_ok and parsed then
                        -- Gemini wraps content in candidates[].content.parts[].text
                        if parsed.candidates and parsed.candidates[1] then
                            local ai_text = parsed.candidates[1].content and 
                                parsed.candidates[1].content.parts and 
                                parsed.candidates[1].content.parts[1] and 
                                parsed.candidates[1].content.parts[1].text
                            if ai_text then
                                local inner_ok, inner = pcall(json_req.decode, ai_text)
                                valid_json = inner_ok and inner ~= nil
                                if not valid_json then
                                    -- Try to find JSON boundaries for truncated responses
                                    local first_brace = ai_text:find("{", 1, true)
                                    if first_brace then
                                        valid_json = true -- Let main thread's fixTruncatedJSON handle it
                                    end
                                end
                            end
                        -- ChatGPT wraps content in choices[].message.content
                        elseif parsed.choices and parsed.choices[1] then
                            local content = parsed.choices[1].message and parsed.choices[1].message.content
                            if content then
                                local inner_ok, inner = pcall(json_req.decode, content)
                                valid_json = inner_ok and inner ~= nil
                                if not valid_json then
                                    local first_brace = content:find("{", 1, true)
                                    if first_brace then
                                        valid_json = true
                                    end
                                end
                            end
                        end
                    end
                    
                    if valid_json then
                        -- Success! Write result to file and exit loop
                        local f = io.open(result_file, "w")
                        if f then
                            f:write(tostring(code) .. "\n")
                            f:write(req.provider .. "\n")
                            f:write(response_text)
                            f:close()
                            self:log("AIHelper Child: Result written to " .. result_file)
                            success_found = true
                            break
                        else
                            self:log("AIHelper Child: Failed to open result file " .. result_file)
                        end
                    else
                        self:log(string.format("AIHelper Child: Provider %s returned 200 but JSON is invalid/truncated. Trying fallback.", req.provider))
                        -- Fall through to try the next provider
                        if i == #requests then
                            -- Last provider also failed validation — write it anyway so main thread can attempt repair
                            local f = io.open(result_file, "w")
                            if f then
                                f:write(tostring(code) .. "\n")
                                f:write(req.provider .. "\n")
                                f:write(response_text)
                                f:close()
                            end
                        end
                    end
                else
                    self:log(string.format("AIHelper Child: Provider %s failed with code %s", req.provider, tostring(code)))
                    -- If it's the last one, write the error
                    if i == #requests then
                        local f = io.open(result_file, "w")
                        if f then
                            f:write(tostring(code) .. "\n")
                            f:write(req.provider .. "\n")
                            f:write(response_text)
                            f:close()
                        end
                    end
                end
            end
            socketutil_req:reset_timeout()
        end)
        
        if not child_ok then
            self:log("AIHelper Child: CRITICAL ERROR: " .. tostring(child_err))
            local f = io.open(result_file, "w")
            if f then
                f:write("ERROR\n")
                f:write("unknown\n")
                f:write(tostring(child_err))
                f:close()
            end
        end

        -- Close write_fd if provided by runInSubProcess
        if write_fd and write_fd > 0 then
            pcall(function() 
                local ffi = require("ffi")
                ffi.cdef[[ int close(int fd); ]]
                ffi.C.close(write_fd) 
            end)
        end

        -- Exit child cleanly
        local posix_ok, posix = pcall(require, "posix.unistd")
        if posix_ok and posix and posix._exit then
            posix._exit(0)
        else
            os.exit(0)
        end
    end

    -- Method 1: ffiutil.runInSubProcess (Preferred KOReader pattern)
    if ok_ffi and ffiutil and ffiutil.runInSubProcess then
        self:log("AIHelper: Trying ffiutil.runInSubProcess")
        local pid, read_fd = ffiutil.runInSubProcess(child_logic, true)
        if pid and pid > 0 then
            self:log("AIHelper: runInSubProcess started PID " .. tostring(pid))
            -- We don't need the pipe for now as we use the result_file
            if read_fd and read_fd > 0 then
                pcall(function() 
                    local ffi = require("ffi")
                    ffi.cdef[[ int close(int fd); ]]
                    ffi.C.close(read_fd) 
                end)
            end
            self._async_child_pid = pid
            return true
        end
    end

    -- Method 2: Manual fork fallbacks
    local fork = nil
    if ok_ffi and ffiutil and ffiutil.fork then
        fork = ffiutil.fork
    else
        local ok_posix, posix = pcall(require, "posix.unistd")
        if not ok_posix then ok_posix, posix = pcall(require, "posix") end
        if ok_posix and posix and posix.fork then
            fork = posix.fork
        else
            local ok_f, ffi = pcall(require, "ffi")
            if ok_f then
                pcall(function()
                    ffi.cdef[[ int fork(void); ]]
                    fork = ffi.C.fork
                end)
            end
        end
    end
    
    if fork then
        local pid = fork()
        if pid == 0 then
            child_logic(0, nil)
            return true -- unreachable
        elseif pid and pid > 0 then
            self:log("AIHelper: Manual fork started PID " .. tostring(pid))
            self._async_child_pid = pid
            return true
        end
    end

    self:log("AIHelper: All background fetch methods failed")
    return false
end

-- Check if the async result file exists and parse it. Returns:
--   nil (still pending)
--   book_data table (success)
--   false, error_code, error_msg (failed)
function AIHelper:checkAsyncResult(result_file)
    local f = io.open(result_file, "r")
    if not f then return nil end  -- still pending

    local content = f:read("*a")
    f:close()
    os.remove(result_file)

    -- Reap child process to prevent zombies
    if self._async_child_pid then
        pcall(function()
            local posix_sys = require("posix.sys.wait")
            posix_sys.wait(self._async_child_pid, posix_sys.WNOHANG)
        end)
        self._async_child_pid = nil
    end

    -- Parse: first line = code, second line = provider, rest = response body
    local first_newline = content:find("\n")
    if not first_newline then return false, "error_parse", "Malformed async result" end
    local code_str = content:sub(1, first_newline - 1)
    local rest = content:sub(first_newline + 1)
    local second_newline = rest:find("\n")
    if not second_newline then return false, "error_parse", "Malformed async result" end
    local provider = rest:sub(1, second_newline - 1)
    local response_text = rest:sub(second_newline + 1)

    if code_str == "ERROR" then
        return false, "error_api", response_text
    end

    local code_num = tonumber(code_str)
    if code_num ~= 200 or not response_text or #response_text == 0 then
        return false, "error_api", "HTTP " .. tostring(code_num)
    end

    -- Parse the response based on provider
    local success, data = pcall(json.decode, response_text)
    if not success then return false, "error_parse", "JSON decode failed" end

    local ai_text
    if provider == "gemini" then
        if data.candidates and data.candidates[1] and
           data.candidates[1].content and data.candidates[1].content.parts and
           data.candidates[1].content.parts[1] then
            ai_text = data.candidates[1].content.parts[1].text
        end
    else
        if data.choices and data.choices[1] then
            ai_text = data.choices[1].message.content
        end
    end

    if not ai_text then return false, "error_parse", "No text in AI response" end

    local parsed_data, parse_err = self:parseAIResponse(ai_text)
    if parsed_data then
        return parsed_data
    else
        return false, "error_parse", tostring(parse_err)
    end
end

function AIHelper:init(path)
    self.path = path or "plugins/xray.koplugin"
    self:loadConfig(); self:loadSettings()
    self:log("AIHelper initialized")
end

function AIHelper:loadConfig()
    local new_config_file = self.path .. "/xray_config.lua"
    local old_config_file = self.path .. "/config.lua"
    
    -- Graceful migration for existing config.lua users
    local old_f = io.open(old_config_file, "r")
    if old_f then
        old_f:close()
        local old_success, old_config = pcall(dofile, old_config_file)
        if old_success and type(old_config) == "table" then
            local has_keys = false
            if old_config.gemini_api_key and #old_config.gemini_api_key > 0 then has_keys = true end
            if old_config.chatgpt_api_key and #old_config.chatgpt_api_key > 0 then has_keys = true end
            if has_keys then
                self:log("AIHelper: Migrating user keys from old config.lua to xray_config.lua")
                local new_f = io.open(new_config_file, "r")
                if new_f then
                    local new_text = new_f:read("*a")
                    new_f:close()
                    if old_config.gemini_api_key and #old_config.gemini_api_key > 0 then
                        new_text = new_text:gsub('gemini_api_key%s*=%s*""', 'gemini_api_key = "' .. old_config.gemini_api_key .. '"')
                    end
                    if old_config.chatgpt_api_key and #old_config.chatgpt_api_key > 0 then
                        new_text = new_text:gsub('chatgpt_api_key%s*=%s*""', 'chatgpt_api_key = "' .. old_config.chatgpt_api_key .. '"')
                    end
                    local out_f = io.open(new_config_file, "w")
                    if out_f then
                        out_f:write(new_text)
                        out_f:close()
                    end
                end
                os.remove(old_config_file)
            else
                os.remove(old_config_file)
            end
        else
            os.rename(old_config_file, old_config_file .. ".bak")
        end
    end

    local success, config = pcall(dofile, new_config_file)
    self.config_keys = { gemini = nil, chatgpt = nil }
    if success and config then
        if config.gemini_api_key then self.providers.gemini.api_key = config.gemini_api_key; self.config_keys.gemini = config.gemini_api_key end
        if config.gemini_primary_model then self.providers.gemini.primary_model = config.gemini_primary_model end
        if config.gemini_secondary_model then self.providers.gemini.secondary_model = config.gemini_secondary_model end
        if config.chatgpt_api_key then self.providers.chatgpt.api_key = config.chatgpt_api_key; self.config_keys.chatgpt = config.chatgpt_api_key end
        if config.chatgpt_model then self.providers.chatgpt.model = config.chatgpt_model end
        if config.default_provider then self.default_provider = config.default_provider end
    end
end

function AIHelper:loadSettings()
    local DataStorage = require("datastorage")
    local xray_dir = DataStorage:getSettingsDir() .. "/xray"
    
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or type(lfs) ~= "table" then
        ok, lfs = pcall(require, "lfs")
    end
    if not ok or type(lfs) ~= "table" then
        self:log("CRITICAL ERROR: Failed to load 'lfs' module in loadSettings. Settings will not be loaded. Error: " .. tostring(lfs))
        return
    end
    if lfs.attributes(xray_dir, "mode") ~= "directory" then
        lfs.mkdir(xray_dir)
    end
    
    local settings = {}
    local settings_file = xray_dir .. "/settings.json"
    
    -- Migration from old .txt files
    local migrated = false
    local function migrate_file(filename, key)
        local f = io.open(xray_dir .. "/" .. filename, "r")
        if f then
            local val = f:read("*a"):match("^%s*(.-)%s*$")
            f:close()
            if val and #val > 0 then
                settings[key] = val
                migrated = true
            end
            os.remove(xray_dir .. "/" .. filename)
        end
    end
    
    migrate_file("default_provider.txt", "default_provider")
    migrate_file("gemini_api_key.txt", "gemini_api_key")
    migrate_file("chatgpt_api_key.txt", "chatgpt_api_key")
    migrate_file("language.txt", "language")
    
    -- Load existing settings.json if it exists
    local f = io.open(settings_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local success, decoded = pcall(json.decode, content)
        if success and type(decoded) == "table" then
            for k, v in pairs(decoded) do
                settings[k] = v
            end
        end
    end
    
    -- Ensure config values are used as initial defaults if not in settings.json
    if not settings.gemini_primary_model then settings.gemini_primary_model = self.providers.gemini.primary_model end
    if not settings.gemini_secondary_model then settings.gemini_secondary_model = self.providers.gemini.secondary_model end
    if not settings.chatgpt_model then settings.chatgpt_model = self.providers.chatgpt.model end
    
    -- Migration to unified Primary and Secondary AI logic
    if not settings.primary_ai then
        local def_prov = settings.default_provider or "gemini"
        if def_prov == "gemini" then
            settings.primary_ai = { provider = "gemini", model = settings.gemini_primary_model or "gemini-2.5-flash" }
            settings.secondary_ai = { provider = "gemini", model = settings.gemini_secondary_model or "gemini-2.5-flash-lite" }
        else
            settings.primary_ai = { provider = "chatgpt", model = settings.chatgpt_model or "gpt-4o-mini" }
            settings.secondary_ai = { provider = "gemini", model = "gemini-2.5-flash-lite" }
        end
        migrated = true
    end
    
    if migrated then
        self.settings = settings
        self:saveSettings()
    end
    
    self.settings = settings
    self.current_language = settings.language or "en"
    
    if settings.gemini_api_key then 
        if settings.gemini_use_ui_key ~= false then
            self.providers.gemini.api_key = settings.gemini_api_key
            self.providers.gemini.ui_key_active = true
        else
            self.providers.gemini.ui_key_active = false
        end
    end
    
    if settings.chatgpt_api_key then 
        if settings.chatgpt_use_ui_key ~= false then
            self.providers.chatgpt.api_key = settings.chatgpt_api_key
            self.providers.chatgpt.ui_key_active = true
        else
            self.providers.chatgpt.ui_key_active = false
        end
    end
    
    self:loadLanguage()
end

function AIHelper:saveSettings(new_settings)
    local DataStorage = require("datastorage")
    local xray_dir = DataStorage:getSettingsDir() .. "/xray"
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or type(lfs) ~= "table" then
        ok, lfs = pcall(require, "lfs")
    end
    if not ok or type(lfs) ~= "table" then
        self:log("CRITICAL ERROR: Failed to load 'lfs' module in saveSettings. Settings will not be saved. Error: " .. tostring(lfs))
        return
    end
    if lfs.attributes(xray_dir, "mode") ~= "directory" then
        lfs.mkdir(xray_dir)
    end
    
    self.settings = self.settings or {}
    if new_settings then
        for k, v in pairs(new_settings) do
            self.settings[k] = v
        end
    end
    
    local settings_file = xray_dir .. "/settings.json"
    local f = io.open(settings_file, "w")
    if f then
        f:write(json.encode(self.settings))
        f:close()
    end
end

function AIHelper:loadLanguage()
    local en_file = self.path .. "/prompts/en.lua"
    local ok_en, en_prompts = pcall(dofile, en_file)
    self.prompts = ok_en and en_prompts or {}
    if self.current_language ~= "en" then
        local loc_file = self.path .. "/prompts/" .. self.current_language .. ".lua"
        local ok_loc, loc_prompts = pcall(dofile, loc_file)
        if ok_loc and type(loc_prompts) == "table" then for k, v in pairs(loc_prompts) do self.prompts[k] = v end end
    end
end

function AIHelper:createPrompt(title, author, context, section_name)
    if not self.prompts then self:loadLanguage() end
    section_name = section_name or "character_section"
    local template = self.prompts[section_name] or self.prompts.character_section
    local enhanced_title, enhanced_author, extra_context = title, author or "Unknown", ""
    if context then
        if context.series then enhanced_title = enhanced_title .. " | Series: " .. context.series end
        if context.book_text then extra_context = extra_context .. "\n\nBOOK TEXT CONTEXT:\n" .. context.book_text end
        -- Chapter data is only relevant for comprehensive fetches, not "more characters" or author lookups
        if section_name == "comprehensive_xray" then
            if context.chapter_titles and #context.chapter_titles > 0 then
                local numbered_chapters = {}
                for i, t in ipairs(context.chapter_titles) do
                    table.insert(numbered_chapters, string.format("%d. %s", i, t))
                end
                extra_context = extra_context .. "\n\nLIST OF CHAPTERS (Provide EXACTLY 1 event for EACH, in order):\n[TOTAL CHAPTER COUNT: " .. #context.chapter_titles .. "]\n" .. table.concat(numbered_chapters, "\n")
            end
            if context.chapter_samples then extra_context = extra_context .. "\n\nCHAPTER SAMPLES:\n" .. context.chapter_samples end
        end
        if context.annotations then extra_context = extra_context .. "\n\nUSER HIGHLIGHTS:\n" .. context.annotations end
        -- Merge mode: tell AI what we already know
        local has_merge_data = false
        local merge_instructions = "\n\nMERGE MODE INSTRUCTIONS:\nYou are UPDATING an existing X-Ray.\n- For entities (Characters, Locations, Historical Figures) that already exist, synthesize a completely rewritten, cohesive summary combining the EXISTING KNOWLEDGE with any new information found in the text.\n- Write a solid summary that is not repetitive.\n- Descriptions MUST NOT exceed 500 characters.\n- If there is no new information, return the existing description (or a refined version of it under 500 characters)."
        
        if context.existing_characters and #context.existing_characters > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, c in ipairs(context.existing_characters) do
                if c.name and c.description then
                    -- CONTEXT TRIMMING: Only send full descriptions for characters that appear in the sample
                    -- Otherwise just send the name to allow the AI to mention them if they appear
                    if sample_text:find(c.name) then
                        table.insert(existing_lines, "- " .. c.name .. ": " .. c.description)
                    else
                        table.insert(existing_lines, "- " .. c.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING CHARACTER KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
        
        if context.existing_historical_figures and #context.existing_historical_figures > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, h in ipairs(context.existing_historical_figures) do
                if h.name and h.biography then
                    if sample_text:find(h.name) then
                        table.insert(existing_lines, "- " .. h.name .. ": " .. h.biography)
                    else
                        table.insert(existing_lines, "- " .. h.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING HISTORICAL FIGURE KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
        
        if context.existing_locations and #context.existing_locations > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, l in ipairs(context.existing_locations) do
                if l.name and l.description then
                    if sample_text:find(l.name) then
                        table.insert(existing_lines, "- " .. l.name .. ": " .. l.description)
                    else
                        table.insert(existing_lines, "- " .. l.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING LOCATION KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
    end
    local p = (context and context.reading_percent) or 100
    local success, final_prompt
    if section_name == "more_characters" then
        local exclude = context.exclude_characters or ""
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, exclude, p)
    else
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p)
    end
    if not success then final_prompt = string.format("Book: %s - Author: %s. Extract %s data.", enhanced_title, enhanced_author, section_name) end
    if #extra_context > 0 then final_prompt = final_prompt .. extra_context end
    return final_prompt
end

function AIHelper:executeUnifiedRequest(prompt)
    local primary = self.settings.primary_ai or { provider = "gemini", model = "gemini-2.5-flash" }
    local secondary = self.settings.secondary_ai or { provider = "gemini", model = "gemini-2.5-flash-lite" }
    
    local models_to_try = { primary, secondary }
    local last_err = "No models configured."
    
    for _, ai in ipairs(models_to_try) do
        local config = self.providers[ai.provider]
        if not config or not config.api_key or config.api_key == "" then
            self:log("AIHelper: Skipping " .. ai.provider .. " (" .. ai.model .. ") - API Key missing")
            last_err = "API Key not set for " .. (ai.provider == "gemini" and "Google Gemini" or "ChatGPT")
        else
            self:log("AIHelper: Trying unified fallback model: " .. ai.provider .. " / " .. ai.model)
            local result, err_code, err_msg
            if ai.provider == "gemini" then
                result, err_code, err_msg = self:callGemini(prompt, config, ai.model)
            else
                result, err_code, err_msg = self:callChatGPT(prompt, config, ai.model)
            end
            
            if result then return result end
            self:log("AIHelper: Model failed: " .. tostring(err_msg))
            last_err = err_msg or "Unknown API Error"
        end
    end
    return nil, "error_api", last_err
end

function AIHelper:getBookDataSection(title, author, provider_name, context, section_name)
    local prompt = self:createPrompt(title, author, context, section_name)
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:getAuthorData(title, author, provider_name, context)
    local prompt = self:createPrompt(title, author, context, "author_only")
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:getMoreCharacters(title, author, provider_name, context)
    return self:getBookDataSection(title, author, provider_name, context, "more_characters")
end

function AIHelper:getBookDataComprehensive(title, author, provider_name, context)
    local prompt = self:createPrompt(title, author, context, "comprehensive_xray")
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:callGemini(prompt, config, current_model)
    current_model = current_model or "gemini-2.0-flash"
    local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
    self:log("AIHelper: Gemini Prompt prepared")
    
    local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. current_model .. ":generateContent"
    local request_body = json.encode({
        contents = {{ role = "user", parts = {{ text = prompt }} }},
        system_instruction = { parts = {{ text = system_instruction_text }} },
        generationConfig = { temperature = 0.2, maxOutputTokens = 16384 }
    })
    self:log("AIHelper: Sending Gemini request (" .. #request_body .. " bytes)")
    local ok, code, response_text, status = self:makeRequest(url, { ["Content-Type"] = "application/json", ["x-goog-api-key"] = config.api_key }, request_body)
    local code_num = tonumber(code)
    self:log("AIHelper: [" .. current_model .. "] Response Code: " .. tostring(code_num))
    self:log("AIHelper: [" .. current_model .. "] Response received (" .. (response_text and #response_text or 0) .. " bytes)")
    
    if code_num == 200 and response_text then
        local success, data = pcall(json.decode, response_text)
        if success and data.candidates and data.candidates[1] then
            local candidate = data.candidates[1]
            if candidate.content and candidate.content.parts and candidate.content.parts[1] then
                local ai_text = candidate.content.parts[1].text
                local parsed_data, err = self:parseAIResponse(ai_text)
                if parsed_data then
                    return parsed_data
                else
                    self:log("AIHelper: [" .. current_model .. "] Parse failed: " .. tostring(err))
                    return nil, "error_parse", "Parse failed: " .. tostring(err)
                end
            end
        end
    elseif code_num == 429 then return nil, "error_quota", "Quota Exceeded (429)"
    elseif code_num == 503 then self:log("AIHelper: 503 Overload"); socket.sleep(2)
    else
        local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
        if response_text then
            local s, err_data = pcall(json.decode, response_text)
            if s and err_data and err_data.error then error_detail = err_data.error.message or error_detail end
        end
        return nil, "error_api", error_detail
    end
    return nil, "error_parse", "Failed to return valid JSON."
end

function AIHelper:callChatGPT(prompt, config, current_model)
    local model = current_model or "gpt-4o-mini"
    self:log("AIHelper: Starting ChatGPT request for model: " .. model)
    
    local legacy_models = { ["gpt-4"] = true, ["gpt-3.5-turbo"] = true, ["gpt-4-32k"] = true }
    if legacy_models[model] then
        local err = "Model '" .. model .. "' does not support JSON mode. Please use gpt-4o, gpt-4-turbo, or gpt-4o-mini."
        self:log("AIHelper: " .. err)
        return nil, "error_api", err
    end

    self:log("AIHelper: ChatGPT Prompt prepared")
    local request_body = json.encode({ model = model, messages = {{ role = "user", content = prompt }}, response_format = { type = "json_object" }, max_tokens = 8192 })
    self:log("AIHelper: Sending ChatGPT request (" .. #request_body .. " bytes)")
    local ok, code, response_text = self:makeRequest(config.endpoint or "https://api.openai.com/v1/chat/completions", { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.api_key }, request_body)
    
    local code_num = tonumber(code)
    self:log("AIHelper: ChatGPT Response Code: " .. tostring(code_num))
    self:log("AIHelper: ChatGPT Response received (" .. (response_text and #response_text or 0) .. " bytes)")
    
    if code_num == 200 and response_text then 
        local success, data = pcall(json.decode, response_text)
        if success and data.choices and data.choices[1] then
            local parsed_data, err = self:parseAIResponse(data.choices[1].message.content)
            if parsed_data then return parsed_data end
            self:log("AIHelper: ChatGPT parse failed: " .. tostring(err))
        end
    else
        local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
        if response_text then
            local s, err_data = pcall(json.decode, response_text)
            if s and err_data and err_data.error then 
                error_detail = err_data.error.message or error_detail 
            end
            self:log("AIHelper: ChatGPT API Error: " .. response_text)
        end
        return nil, "error_api", error_detail
    end
    
    return nil, "error_api", "ChatGPT failed or returned invalid JSON"
end

local function normalizeKeys(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        local new_k = type(k) == "string" and k:lower():gsub("%s+", "_") or k
        if type(v) == "table" then res[new_k] = normalizeKeys(v) else res[new_k] = v end
    end
    return res
end

local function fixTruncatedJSON(s)
    local stack, in_string, escaped = {}, false, false
    for i = 1, #s do
        local c = s:sub(i,i)
        if escaped then escaped = false
        elseif c == "\\" then escaped = true
        elseif c == '"' then in_string = not in_string
        elseif not in_string then
            if c == "{" or c == "[" then table.insert(stack, c)
            elseif c == "}" then if #stack > 0 and stack[#stack] == "{" then table.remove(stack) end
            elseif c == "]" then if #stack > 0 and stack[#stack] == "[" then table.remove(stack) end end
        end
    end
    local res = s
    if in_string then res = res .. '"' end
    
    -- Ensure we remove any trailing commas before closing
    res = res:gsub(",%s*$", "")
    
    for i = #stack, 1, -1 do 
        if stack[i] == "{" then 
            res = res .. "}" 
        else 
            res = res .. "]" 
        end 
    end
    return res
end

function AIHelper:parseAIResponse(text)
    if not text or #text == 0 then return nil, "Empty response" end
    
    -- Aggressively clean up markdown and find JSON boundaries
    local json_text = text:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Method 1: Clean standard markdown blocks
    if json_text:find("^```") then
        json_text = json_text:gsub("^```json%s*", ""):gsub("^```%w*%s*", ""):gsub("```%s*$", "")
    end
    
    -- Method 2: Locate first { and last } if decode fails
    local success, data = pcall(json.decode, json_text)
    if not success then
        self:log("AIHelper: JSON repair needed")
        local first = json_text:find("{", 1, true) or json_text:find("[", 1, true)
        local last_brace = json_text:reverse():find("}", 1, true)
        local last_bracket = json_text:reverse():find("]", 1, true)
        local last_rel = math.max(last_brace or 0, last_bracket or 0)
        
        if first then
             local last = (last_rel > 0) and (#json_text - last_rel + 1) or #json_text
             local extracted = json_text:sub(first, last)
             local fixed = fixTruncatedJSON(extracted)
             
             success, data = pcall(json.decode, fixed)
             if not success and rapidjson_ok then
                 local standard_json = require("json")
                 if standard_json and standard_json ~= json then 
                     success, data = pcall(standard_json.decode, fixed) 
                 end
             end
        end
    end
    
    if success and data then return self:validateAndCleanData(normalizeKeys(data)) end
    self:log("AIHelper: Parse failed. Snippet: " .. tostring(text):sub(1, 150))
    return nil, "Failed to parse JSON"
end

function AIHelper:validateAndCleanData(data)
    if not data then return nil end
    local strings = self:getFallbackStrings()
    local function ensureString(v, d) return (type(v) == "string" and #v > 0) and v or d or "" end
    
    local chars = data.characters or data.Characters or {}
    local valid_chars = {}
    for _, c in ipairs(chars) do
        if type(c) == "table" then
            table.insert(valid_chars, {
                name = ensureString(c.name or c.full_formal_name or c.Name, strings.unnamed_character),
                role = ensureString(c.role or c.Role, strings.not_specified),
                description = ensureString(c.description or c.bio or c.history or c.desc, strings.no_description),
                gender = ensureString(c.gender or c.Gender, ""),
                occupation = ensureString(c.occupation or c.job or c.Occupation, "")
            })
        end
    end
    data.characters = valid_chars
    
    local hists = data.historical_figures or data.historicalfigures or {}
    local valid_hists = {}
    for _, h in ipairs(hists) do
        if type(h) == "table" then
            table.insert(valid_hists, {
                name = ensureString(h.name or h.Name, strings.unnamed_person),
                biography = ensureString(h.biography or h.bio or h.description, strings.no_biography),
                role = ensureString(h.role or h.historical_role, ""),
                importance_in_book = ensureString(h.importance_in_book or h.significance, "Mentioned"),
                context_in_book = ensureString(h.context_in_book or h.context, "Historical")
            })
        end
    end
    data.historical_figures = valid_hists
    
    local locs = data.locations or data.Locations or {}
    local valid_locs = {}
    for _, l in ipairs(locs) do
        if type(l) == "table" then
            table.insert(valid_locs, {
                name = ensureString(l.name or l.place or l.Lugar, "Unknown Place"),
                description = ensureString(l.description or l.desc or l.short_desc, ""),
                importance = ensureString(l.importance or l.significance, "")
            })
        end
    end
    data.locations = valid_locs
    
    data.timeline = data.timeline or data.Timeline or {}
    
    -- Sanitize author info if present
    if data.author or data.author_bio or data.author_birth or data.author_death then
        local strings = self:getFallbackStrings()
        local function ensureString(v, d) return (type(v) == "string" and #v > 0) and v or d or "" end
        data.author = ensureString(data.author, strings.unknown_author)
        data.author_bio = ensureString(data.author_bio, strings.no_biography)
        data.author_birth = ensureString(data.author_birth, "---")
        data.author_death = ensureString(data.author_death, "---")
    end
    
    return data
end

function AIHelper:getFallbackStrings()
    return self.prompts and self.prompts.fallback or {}
end

function AIHelper:setAPIKey(p, k) 
    self.providers[p].api_key = k
    self.providers[p].ui_key_active = true
    self:saveSettings({ [p .. "_api_key"] = k, [p .. "_use_ui_key"] = true })
    return true 
end

function AIHelper:setUnifiedModel(type, provider, model)
    if type == "primary" then
        self.settings.primary_ai = { provider = provider, model = model }
    elseif type == "secondary" then
        self.settings.secondary_ai = { provider = provider, model = model }
    end
    self:saveSettings()
    return true
end

return AIHelper
