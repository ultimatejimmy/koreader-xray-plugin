-- AIHelper - Google Gemini & ChatGPT for X-Ray
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
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
            primary_model = "gemini-2.5-flash",
            secondary_model = "gemini-2.5-flash-lite",
        },
        chatgpt = {
            name = "ChatGPT",
            enabled = true,
            api_key = nil,
            endpoint = "https://api.openai.com/v1/chat/completions",
            model = "gpt-4o-mini",
        }
    },
    default_provider = nil,
    current_language = "en",
    prompts = nil,
    trap_widget = nil,
}

-- Custom logger for X-Ray
function AIHelper:log(message)
    if not self.path then return end
    local log_path = self.path .. "/xray.log"
    local f = io.open(log_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message) .. "\n")
        f:close()
    end
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
        if ok == nil and code == nil then return performRequest() end
        return ok, code, response_text, status
    else return performRequest() end
end

function AIHelper:init(path)
    self.path = path or "plugins/xray.koplugin"
    local f = io.open(self.path .. "/xray.log", "a")
    if f then
        f:write("\n" .. string.rep("=", 40) .. "\n")
        f:write("--- X-Ray Session Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
        f:close()
    end
    self:loadConfig(); self:loadModelFromFile(); self:loadLanguage()
    self:log("AIHelper initialized")
end

function AIHelper:loadConfig()
    local config_file = self.path .. "/config.lua"
    local success, config = pcall(dofile, config_file)
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

function AIHelper:loadModelFromFile()
    local DataStorage = require("datastorage")
    local xray_dir = DataStorage:getSettingsDir() .. "/xray"
    local provider_file = io.open(xray_dir .. "/default_provider.txt", "r")
    if provider_file then
        local provider = provider_file:read("*a"):match("^%s*(.-)%s*$"); provider_file:close()
        if provider and (provider == "gemini" or provider == "chatgpt") then self.default_provider = provider end
    end
    local function read_key(n, p)
        local f = io.open(xray_dir .. "/" .. n, "r")
        if f then
            local k = f:read("*a"):gsub("%s+", ""); f:close()
            if #k > 0 then self.providers[p].api_key = k; self.providers[p].ui_key_active = true; return end
        end
        self.providers[p].ui_key_active = false
        if self.config_keys and self.config_keys[p] then self.providers[p].api_key = self.config_keys[p] end
    end
    read_key("gemini_api_key.txt", "gemini"); read_key("chatgpt_api_key.txt", "chatgpt")
end

function AIHelper:loadLanguage()
    local DataStorage = require("datastorage")
    local f = io.open(DataStorage:getSettingsDir() .. "/xray/language.txt", "r")
    self.current_language = f and f:read("*a"):match("^%s*(.-)%s*$") or "en"
    if f then f:close() end
    self:loadPrompts()
end

function AIHelper:loadPrompts()
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
        if context.chapter_samples then extra_context = extra_context .. "\n\nCHAPTER SAMPLES:\n" .. context.chapter_samples end
        if context.annotations then extra_context = extra_context .. "\n\nUSER HIGHLIGHTS:\n" .. context.annotations end
    end
    local p = (context and context.reading_percent) or 100
    local success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p)
    if not success then final_prompt = string.format("Book: %s - Author: %s. Extract %s data.", enhanced_title, enhanced_author, section_name) end
    if #extra_context > 0 then final_prompt = final_prompt .. extra_context end
    return final_prompt
end

function AIHelper:getBookDataSection(title, author, provider_name, context, section_name)
    self:loadConfig()
    local provider = provider_name or "gemini"
    local config = self.providers[provider]
    if not config or not config.api_key then return nil, "error_no_api_key", "API Key not set." end
    local prompt = self:createPrompt(title, author, context, section_name)
    if provider == "gemini" then return self:callGemini(prompt, config)
    else return self:callChatGPT(prompt, config) end
end

function AIHelper:getAuthorData(title, author, provider_name)
    return self:getBookDataSection(title, author, provider_name, nil, "author_only")
end

function AIHelper:getBookDataComprehensive(title, author, provider_name, context)
    self:loadConfig()
    local provider = provider_name or "gemini"
    local config = self.providers[provider]
    if not config or not config.api_key then return nil, "error_no_api_key", "API Key not set." end
    
    local prompt = self:createPrompt(title, author, context, "comprehensive_xray")
    if provider == "gemini" then return self:callGemini(prompt, config)
    else return self:callChatGPT(prompt, config) end
end

function AIHelper:callGemini(prompt, config)
    local primary = config.primary_model or "gemini-2.5-flash"
    local secondary = config.secondary_model or "gemini-2.5-flash-lite"
    local fallback_chain = { primary, secondary, "gemini-1.5-flash-8b" }
    local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
    self:log("AIHelper: Gemini Prompt prepared")
    for _, current_model in ipairs(fallback_chain) do
        self:log("AIHelper: Trying model: " .. current_model)
        local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. current_model .. ":generateContent"
        local request_body = json.encode({
            contents = {{ role = "user", parts = {{ text = prompt }} }},
            system_instruction = { parts = {{ text = system_instruction_text }} },
            generationConfig = { temperature = 0.2, maxOutputTokens = 8192 }
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
                    return self:parseAIResponse(candidate.content.parts[1].text)
                end
            end
        elseif code_num == 429 then return nil, "error_quota", "Quota Exceeded (429)"
        elseif code_num == 503 then self:log("AIHelper: 503 Overload. Falling back..."); socket.sleep(2)
        else
            local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
            if response_text then
                local s, err_data = pcall(json.decode, response_text)
                if s and err_data and err_data.error then error_detail = err_data.error.message or error_detail end
            end
            return nil, "error_api", error_detail
        end
    end
    return nil, "error_503", "All models busy (503)"
end

function AIHelper:callChatGPT(prompt, config)
    self:log("AIHelper: Starting ChatGPT request")
    self:log("AIHelper: ChatGPT Prompt prepared")
    local request_body = json.encode({ model = config.model or "gpt-4o-mini", messages = {{ role = "user", content = prompt }}, response_format = { type = "json_object" } })
    self:log("AIHelper: Sending ChatGPT request (" .. #request_body .. " bytes)")
    local ok, code, response_text = self:makeRequest(config.endpoint or "https://api.openai.com/v1/chat/completions", { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.api_key }, request_body)
    self:log("AIHelper: ChatGPT Response Code: " .. tostring(code))
    self:log("AIHelper: ChatGPT Response received (" .. (response_text and #response_text or 0) .. " bytes)")
    if tonumber(code) == 200 then local data = json.decode(response_text); return self:parseAIResponse(data.choices[1].message.content) end
    return nil, "error_api", "ChatGPT failed"
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

function AIHelper:parseAIResponse(text)
    if not text or #text == 0 then return nil, "Empty response" end
    local json_text = text:gsub("```%w*", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local success, data = pcall(json.decode, json_text)
    if not success then
        self:log("AIHelper: JSON repair needed")
        local first = json_text:find("{", 1, true) or json_text:find("[", 1, true)
        local last_brace = json_text:reverse():find("}", 1, true)
        local last_bracket = json_text:reverse():find("]", 1, true)
        local last = math.max(last_brace or 0, last_bracket or 0)
        if first and last > 0 then
             local extracted = json_text:sub(first, #json_text - last + 1)
             local fixed = fixTruncatedJSON(extracted)
             success, data = pcall(json.decode, fixed)
             if not success and rapidjson_ok then
                 local standard_json = require("json")
                 if standard_json and standard_json ~= json then success, data = pcall(standard_json.decode, fixed) end
             end
        end
    end
    if success and data then return self:validateAndCleanData(normalizeKeys(data)) end
    self:log("AIHelper: Parse failed. Snippet: " .. tostring(text):sub(1, 100))
    return nil, "Failed to parse JSON. Check xray.log."
end

function fixTruncatedJSON(s)
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
    res = res:gsub(",%s*$", "")
    for i = #stack, 1, -1 do if stack[i] == "{" then res = res .. "}" else res = res .. "]" end end
    return res
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
    return data
end

function AIHelper:getFallbackStrings()
    return self.prompts and self.prompts.fallback or {}
end

function AIHelper:setAPIKey(p, k) self.providers[p].api_key = k; return true end
function AIHelper:setDefaultProvider(p) self.default_provider = p; return true end

return AIHelper
