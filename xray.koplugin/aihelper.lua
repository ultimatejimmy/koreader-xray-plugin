-- AIHelper - Google Gemini & ChatGPT for X-Ray
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local Trapper = require("ui/trapper")

-- Optimization: Use rapidjson if available (much faster for large context)
local rapidjson_ok, rapidjson = pcall(require, "rapidjson")
local json = rapidjson_ok and rapidjson or require("json")

local AIHelper = {}

-- AI Provider settings (default values)
AIHelper.providers = {
    gemini = {
        name = "Google Gemini",
        enabled = true,
        api_key = nil,
        model = "gemini-2.5-flash", -- User's preferred model
    },
    chatgpt = {
        name = "ChatGPT",
        enabled = true,
        api_key = nil,
        endpoint = "https://api.openai.com/v1/chat/completions",
        model = "gpt-4o-mini", -- Default model (cost/performance)
    }
}

AIHelper.model_override = nil
AIHelper.trap_widget = nil

function AIHelper:setTrapWidget(trap_widget)
    self.trap_widget = trap_widget
end

function AIHelper:resetTrapWidget()
    self.trap_widget = nil
end

--- Make a request with optional Trapper support
function AIHelper:makeRequest(url, headers, request_body, timeout, maxtime)
    -- Further increased defaults for slow Kindle connections with large context
    timeout = timeout or 300 -- Connection/Inactivity timeout (5 minutes)
    maxtime = maxtime or 900 -- Total transfer timeout (15 minutes)
    
    local function performRequest()
        -- CRITICAL: Re-require modules inside the subprocess!
        local socket = require("socket")
        local http = require("socket.http")
        local https = require("ssl.https")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        local logger = require("logger")
        
        -- Optimization: Disable SSL certificate verification for speed on Kindles
        https.cert_verify = false
        
        -- Use socketutil for more robust timeout management
        socketutil:set_timeout(timeout, maxtime)
        
        local response_body = {}
        -- Use socket.http for the request (it handles https if ssl.https is loaded in KOReader)
        local request = {
            url = url,
            method = "POST",
            headers = headers or {},
            source = ltn12.source.string(request_body or ""),
            -- Use socketutil.table_sink to properly manage maxtime/total duration
            sink = socketutil.table_sink(response_body),
        }
        
        logger.info("AIHelper: Starting network request to", url, "Size:", #request_body)
        
        -- Use direct call and pcall to catch any unexpected crashes
        local ok, code, response_headers, status
        local pcall_ok, pcall_err = pcall(function()
            ok, code, response_headers, status = http.request(request)
        end)
        
        if not pcall_ok then
            logger.warn("AIHelper: Subprocess request crashed: " .. tostring(pcall_err))
            return nil, "error_crash", tostring(pcall_err)
        end
        
        socketutil:reset_timeout()
        
        local response_text = table.concat(response_body)
        logger.info("AIHelper: Request finished. Status code:", code, "Response length:", #response_text)
        
        -- Validate Content-Length to detect truncated downloads
        if response_headers and response_headers["content-length"] then
            local clen = tonumber(response_headers["content-length"])
            if clen and #response_text < clen then
                logger.warn("AIHelper: Incomplete response received (" .. #response_text .. "/" .. clen .. ")")
                return nil, "error_incomplete", "Incomplete response from server"
            end
        end

        -- Check for timeouts in socketutil or luasocket
        if ok == nil and (code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE or code == socketutil.SINK_TIMEOUT_CODE or code == "timeout") then
            logger.warn("AIHelper: Request timed out (code: " .. tostring(code) .. ")")
            return nil, "error_timeout", "Connection timed out"
        end
        
        -- If http.request failed with nil/nil
        if ok == nil and code == nil then
            return nil, "error_unknown_network", "Network request failed without error message"
        end

        -- Return multiple values to be captured by Trapper
        return ok, code, response_text, status
    end

    if self.trap_widget then
        -- Capture multiple return values directly to avoid table construction issues with nils
        -- Trapper:dismissableRunInSubprocess returns: completed (bool), ... (results of func)
        local completed, ok, code, response_text, status = Trapper:dismissableRunInSubprocess(performRequest, self.trap_widget)
        
        if not completed then
            return nil, "USER_CANCELLED", "Request cancelled by user"
        end
        
        -- If subprocess failed silently (common on some Windows/KOReader versions)
        if ok == nil and code == nil then
            logger.warn("AIHelper: Subprocess returned nil values, falling back to main thread")
            return performRequest()
        end
        
        return ok, code, response_text, status
    else
        return performRequest()
    end
end

-- Set Gemini model
function AIHelper:setGeminiModel(model_name)
    if not model_name or #model_name == 0 then return false end
    self.providers.gemini.model = model_name
    self:saveModelToConfig(model_name)
    return true
end

-- Set ChatGPT model
function AIHelper:setChatGPTModel(model_name)
    if not model_name or #model_name == 0 then return false end
    self.providers.chatgpt.model = model_name
    self:saveModelToConfig(model_name, "chatgpt")
    return true
end

-- Set default provider 
function AIHelper:setDefaultProvider(provider_name)
    if not provider_name or (provider_name ~= "gemini" and provider_name ~= "chatgpt") then 
        return false 
    end
    self.default_provider = provider_name
    self:saveProviderToConfig(provider_name)
    logger.info("AIHelper: Default provider changed to:", provider_name)
    return true
end

-- Save model preference to config file
function AIHelper:saveModelToConfig(model_name, provider)
    provider = provider or "gemini"
    local DataStorage = require("datastorage")
    local settings_dir = DataStorage:getSettingsDir()
    local xray_dir = settings_dir .. "/xray"
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(xray_dir)
    
    local model_file = xray_dir .. "/" .. provider .. "_model.txt"
    local file = io.open(model_file, "w")
    if file then
        file:write(model_name)
        file:close()
        return true
    end
    return false
end

-- Save provider preference to config file 
function AIHelper:saveProviderToConfig(provider_name)
    local DataStorage = require("datastorage")
    local settings_dir = DataStorage:getSettingsDir()
    local xray_dir = settings_dir .. "/xray"
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(xray_dir)
    
    local provider_file = xray_dir .. "/default_provider.txt"
    local file = io.open(provider_file, "w")
    if file then
        file:write(provider_name)
        file:close()
        logger.info("AIHelper: Saved default provider:", provider_name)
        return true
    end
    logger.warn("AIHelper: Failed to save provider preference")
    return false
end

-- Initialize AIHelper
function AIHelper:init(path)
    self.path = path or "plugins/xray.koplugin"
    self:loadConfig()
    self:loadModelFromFile()
    self:loadLanguage()
    logger.info("AIHelper: Initialized with Gemini model:", self.providers.gemini.model)
    logger.info("AIHelper: ChatGPT model:", self.providers.chatgpt.model)
end

-- Load configuration
function AIHelper:loadConfig()
    local success, config = pcall(require, "config")
    self.config_keys = { gemini = nil, chatgpt = nil }
    -- INITIALIZE DEFAULT SETTINGS TO PREVENT CRASHES
    self.settings = { auto_fetch_on_open = false, max_characters = 20 } 
    
    if success and config then
        if config.gemini_api_key then 
            self.providers.gemini.api_key = config.gemini_api_key 
            self.config_keys.gemini = config.gemini_api_key
        end
        if config.gemini_model then self.providers.gemini.model = config.gemini_model end
        if config.chatgpt_api_key then 
            self.providers.chatgpt.api_key = config.chatgpt_api_key 
            self.config_keys.chatgpt = config.chatgpt_api_key
        end
        if config.chatgpt_model then self.providers.chatgpt.model = config.chatgpt_model end
        if config.default_provider then self.default_provider = config.default_provider end
        if config.settings then self.settings = config.settings end
    end
end

-- Load model preference
function AIHelper:loadModelFromFile()
    local DataStorage = require("datastorage")
    
    -- Gemini model
    local gemini_file = DataStorage:getSettingsDir() .. "/xray/gemini_model.txt"
    local file = io.open(gemini_file, "r")
    if file then
        local model = file:read("*a"):match("^%s*(.-)%s*$")
        file:close()
        if model and #model > 0 then
            self.providers.gemini.model = model
        end
    end
    
    -- ChatGPT model
    local chatgpt_file = DataStorage:getSettingsDir() .. "/xray/chatgpt_model.txt"
    file = io.open(chatgpt_file, "r")
    if file then
        local model = file:read("*a"):match("^%s*(.-)%s*$")
        file:close()
        if model and #model > 0 then
            self.providers.chatgpt.model = model
        end
    end
    
    -- Default provider
    local provider_file = DataStorage:getSettingsDir() .. "/xray/default_provider.txt"
    file = io.open(provider_file, "r")
    if file then
        local provider = file:read("*a"):match("^%s*(.-)%s*$")
        file:close()
        if provider and (provider == "gemini" or provider == "chatgpt") then
            self.default_provider = provider
            logger.info("AIHelper: Loaded default provider from file:", provider)
        end
    end
    
    -- Gemini API Key
    local gemini_key_file = DataStorage:getSettingsDir() .. "/xray/gemini_api_key.txt"
    file = io.open(gemini_key_file, "r")
    if file then
        local raw_key = file:read("*a")
        file:close()
        if raw_key then
            local clean_key = raw_key:gsub("%s+", "")
            if #clean_key > 0 then
                self.providers.gemini.api_key = clean_key
                self.providers.gemini.ui_key_active = true
                logger.info("AIHelper: Loaded Gemini API key from file")
            end
        end
    else
        self.providers.gemini.ui_key_active = false
        if self.config_keys and self.config_keys.gemini then
            self.providers.gemini.api_key = self.config_keys.gemini
        end
    end
    
    -- ChatGPT API Key
    local chatgpt_key_file = DataStorage:getSettingsDir() .. "/xray/chatgpt_api_key.txt"
    file = io.open(chatgpt_key_file, "r")
    if file then
        local raw_key = file:read("*a")
        file:close()
        if raw_key then
            local clean_key = raw_key:gsub("%s+", "")
            if #clean_key > 0 then
                self.providers.chatgpt.api_key = clean_key
                self.providers.chatgpt.ui_key_active = true
                logger.info("AIHelper: Loaded ChatGPT API key from file")
            end
        end
    else
        self.providers.chatgpt.ui_key_active = false
        if self.config_keys and self.config_keys.chatgpt then
            self.providers.chatgpt.api_key = self.config_keys.chatgpt
        end
    end
end

-- Function to clear the UI override key and revert to config
function AIHelper:clearAPIKeyFile(provider)
    local DataStorage = require("datastorage")
    local key_file = DataStorage:getSettingsDir() .. "/xray/" .. provider .. "_api_key.txt"
    os.remove(key_file)
    if self.config_keys and self.config_keys[provider] then
        self.providers[provider].api_key = self.config_keys[provider]
    else
        self.providers[provider].api_key = nil
    end
    self.providers[provider].ui_key_active = false
    logger.info("AIHelper: Cleared UI key for " .. provider .. ", reverted to config.")
end


-- Save API Key preference to file
function AIHelper:saveAPIKeyToFile(provider, api_key)
    local DataStorage = require("datastorage")
    local settings_dir = DataStorage:getSettingsDir()
    local xray_dir = settings_dir .. "/xray"
    local lfs = require("libs/libkoreader-lfs")
    lfs.mkdir(xray_dir)
    
    local key_file = xray_dir .. "/" .. provider .. "_api_key.txt"
    local file = io.open(key_file, "w")
    if file then
        file:write(api_key)
        file:close()
        logger.info("AIHelper: Saved", provider, "API key to file")
        return true
    end
    logger.warn("AIHelper: Failed to save", provider, "API key")
    return false
end

-- Get author data from AI
function AIHelper:getAuthorData(title, author, provider_name)
    local prompt = self:createAuthorPrompt(title, author)
    local provider = provider_name or self.default_provider or "gemini"
    local config = self.providers[provider]

    if not config or not config.api_key then
        return nil, "error_no_api_key", "AI API Key not set."
    end

    local author_data, error_code, error_msg
    if provider == "gemini" then
        author_data, error_code, error_msg = self:callGemini(prompt, config)
    else
        author_data, error_code, error_msg = self:callChatGPT(prompt, config)
    end

    if author_data then
        return author_data
    end

    return nil, error_code, error_msg
end

function AIHelper:createAuthorPrompt(title, author)
    local lang = self.current_language or "en"
    local prompt_file = self.path .. "/prompts/" .. lang .. ".lua"
    local success, prompts = pcall(dofile, prompt_file)
    
    if not success then
        prompt_file = self.path .. "/prompts/en.lua"
        success, prompts = pcall(dofile, prompt_file)
    end
    
    prompts = prompts or {}
    local template = prompts.author_only or prompts.main
    
    local enhanced_title = title or "Unknown"
    local enhanced_author = author or "Unknown"
    
    return string.format(template, enhanced_title, enhanced_author)
end

function AIHelper:getBookData(title, author, provider_name, context)
    self:loadModelFromFile() -- Refresh model
    local provider = provider_name or "gemini"
    local provider_config = self.providers[provider]
    
    if not provider_config or not provider_config.api_key then
        return nil, "error_no_api_key", "AI API Key not set. Please set it in the settings."
    end
    
    -- Create prompts with context.
    local prompt = self:createPrompt(title, author, context)
    
    logger.info("AIHelper: Using provider:", provider, "Model:", provider_config.model)
    if context and context.spoiler_free then
        logger.info("AIHelper: Spoiler-free mode active, reading:", context.reading_percent, "%")
    end
    
    if provider == "gemini" then
        return self:callGemini(prompt, provider_config)
    elseif provider == "chatgpt" then
        return self:callChatGPT(prompt, provider_config)
    end
    return nil, "error_unknown_provider", "Unsupported AI provider: " .. tostring(provider)
end

-- Load language
function AIHelper:loadLanguage()
    local DataStorage = require("datastorage")
    local f = io.open(DataStorage:getSettingsDir() .. "/xray/language.txt", "r")
    self.current_language = f and f:read("*a"):match("^%s*(.-)%s*$") or "en"
    if f then f:close() end
    self:loadPrompts()
end

-- Load prompts
function AIHelper:loadPrompts()
    -- Use dofile for absolute paths to avoid package.path issues
    local prompt_file = self.path .. "/prompts/" .. self.current_language .. ".lua"
    local success, prompts = pcall(dofile, prompt_file)
    
    if not success then 
        prompt_file = self.path .. "/prompts/en.lua"
        success, prompts = pcall(dofile, prompt_file) 
    end
    self.prompts = prompts or {}
end

-- Create prompt
function AIHelper:createPrompt(title, author, context)
    if not self.prompts then self:loadLanguage() end
    
    local enhanced_title = title
    local enhanced_author = author or "Unknown"
    local extra_context = ""
    
    if context then
        if context.series then
            local series_info = context.series
            if context.series_index then
                series_info = series_info .. " (Book " .. context.series_index .. ")"
            end
            enhanced_title = enhanced_title .. " | Series: " .. series_info
        end
        
        if context.filename or context.pub_year then
            enhanced_title = string.format("%s (File: %s, Year: %s)", 
                enhanced_title, 
                context.filename or "N/A", 
                context.pub_year or "N/A")
        end
        
        if context.chapter_title then
            enhanced_author = enhanced_author .. " | Current Chapter: " .. context.chapter_title
        end
        
        if context.book_text and #context.book_text > 0 then
            extra_context = extra_context .. "\n\nBOOK TEXT CONTEXT (Crucial for identification and progress tracking):\n" .. 
                            "--- START OF TEXT ---\n" .. 
                            context.book_text .. 
                            "\n--- END OF TEXT ---\n"
        end

        if context.chapter_samples and #context.chapter_samples > 0 then
            extra_context = extra_context .. "\n\nCHAPTER SAMPLES (Snapshots from previous chapters for timeline building):\n" ..
                            "--- START OF SAMPLES ---\n" ..
                            context.chapter_samples ..
                            "\n--- END OF SAMPLES ---\n"
        end
        
        if context.annotations and #context.annotations > 0 then
            extra_context = extra_context .. "\n\nUSER HIGHLIGHTS & NOTES (Crucial for character focus):\n" ..
                            "--- START OF ANNOTATIONS ---\n" ..
                            context.annotations ..
                            "\n--- END OF ANNOTATIONS ---\n"
        end
    end
    
    -- Use a custom prompt if context exists and you're in spoiler_free mode.
    local final_prompt = ""
    if context and context.spoiler_free then
        local template = self.prompts.spoiler_free or self.prompts.main
        local p = context.reading_percent
        -- Template expects multiple %d placeholders for strict spoiler rules.
        final_prompt = string.format(template, enhanced_title, enhanced_author, 
            p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p)
        
        -- Add a heavy-handed instruction to use the provided text
        final_prompt = final_prompt .. "\n\nSTRICT INSTRUCTION: Your primary source is the 'BOOK TEXT CONTEXT' and 'USER HIGHLIGHTS' provided above. You MUST NOT reveal any information that is not supported by this text or that obviously happens later in the book. If the text provided does not show a character's secret, DO NOT mention it."
    else
        -- Normal prompt for the full book
        local template = self.prompts.main
        final_prompt = string.format(template, enhanced_title, enhanced_author)
    end
    
    -- Append extra context if available
    if #extra_context > 0 then
        final_prompt = final_prompt .. extra_context
    end
    
    return final_prompt
end

function AIHelper:getFallbackStrings()
    if not self.prompts then self:loadPrompts() end
    return self.prompts.fallback or {}
end

--- Call Google Gemini API
function AIHelper:callGemini(prompt, config)
    logger.info("AIHelper: Calling Google Gemini API")
    
    local model = config.model or "gemini-2.5-flash"
    local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
    
    -- Load the system instruction
    local system_instruction_text = self.prompts and self.prompts.system_instruction or "You are an expert literary critic. Respond ONLY with valid JSON format."

    -- Modern Gemini API: Use system_instruction field and safetySettings
    local request_body = json.encode({
        contents = {{ role = "user", parts = {{ text = prompt }} }},
        system_instruction = { parts = {{ text = system_instruction_text }} },
        safetySettings = {
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
        },
        generationConfig = {
            temperature = 0.4,
            maxOutputTokens = 8192,
            responseMimeType = "application/json"
        }
    })
    
    -- RETRY LOGIC
    local max_retries = 1
    for attempt = 1, max_retries + 1 do
        if attempt > 1 then
             local socket = require("socket")
             socket.sleep(3) 
        end

        local res, code, response_text, status = self:makeRequest(url, {
            ["Content-Type"] = "application/json",
            ["x-goog-api-key"] = config.api_key, -- Modern header auth
            ["Content-Length"] = tostring(#request_body),
        }, request_body, 300, 900) -- Connect timeout 300s, Total 900s
        
        local code_num = tonumber(code)
        logger.info("AIHelper: API Code:", code_num, "Length:", response_text and #response_text or 0)

        if code_num == 200 and response_text then
            local success, data = pcall(json.decode, response_text)
            if not success then return nil, "error_json_parse", "Failed to parse JSON" end
            
            if data and data.candidates and data.candidates[1] then
                local candidate = data.candidates[1]
                
                if candidate.finishReason == "SAFETY" then
                     return nil, "error_safety", "Blocked by Google Safety Filter."
                end
                
                local truncated_warning = ""
                if candidate.finishReason == "MAX_TOKENS" then
                    truncated_warning = "\n\nWARNING: Response was truncated due to output length limits. Some data may be missing."
                    logger.warn("AIHelper: Gemini response truncated (MAX_TOKENS)")
                end

                if candidate.content and candidate.content.parts and candidate.content.parts[1] then
                    local result, err = self:parseAIResponse(candidate.content.parts[1].text)
                    if result then
                        if #truncated_warning > 0 then
                            -- We can't easily append to the data table, but we can log it
                            logger.warn("AIHelper: Returning partial data due to truncation.")
                        end
                        return result
                    else
                        return nil, "error_parse", (err or "Failed to parse AI response.") .. truncated_warning
                    end
                else
                    return nil, "error_api", "API returned an empty response." .. truncated_warning
                end
            else
                return nil, "error_api", "Invalid response format from Google."
            end
        elseif code == "USER_CANCELLED" then
            return nil, "USER_CANCELLED", "Request cancelled"
        elseif code == "error_timeout" then
            return nil, "error_timeout", "Connection timed out"
        elseif code_num == 503 then
             logger.warn("AIHelper: 503 Service Unavailable")
        else
             -- EXTRACT THE EXACT ERROR MESSAGE FROM GOOGLE
             local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
             if response_text then
                 local success, err_data = pcall(json.decode, response_text)
                 if success and err_data and err_data.error then
                     error_detail = err_data.error.message or error_detail
                 end
                 logger.warn("AIHelper: API Error Details: " .. response_text)
             end
             return nil, "error_" .. tostring(code_num or code), "API Error: " .. error_detail
        end
    end
    
    return nil, "error_timeout", "Connection timed out"
end

-- Call ChatGPT API (COMPLETE IMPLEMENTATION)
function AIHelper:callChatGPT(prompt, config)
    logger.info("AIHelper: Calling ChatGPT API")
    
    local model = config.model or "gpt-4o-mini"
    local url = config.endpoint or "https://api.openai.com/v1/chat/completions"
    
    -- Add system instruction (if exists in prompts)
    local system_instruction = self.prompts and self.prompts.system_instruction or 
        "You are an expert literary critic. Respond ONLY with valid JSON format."
    
    local request_body = json.encode({
        model = model,
        messages = {
            {
                role = "system",
                content = system_instruction
            },
            {
                role = "user",
                content = prompt
            }
        },
        temperature = 0.4,
        max_tokens = 8192,
        top_p = 0.95,
        response_format = { type = "json_object" } -- Enforce JSON mode
    })
    
    logger.info("AIHelper: ChatGPT request size:", #request_body)
    
    -- RETRY LOGIC
    local max_retries = 1
    for attempt = 1, max_retries + 1 do
        if attempt > 1 then
             local socket = require("socket")
             socket.sleep(3) 
             logger.info("AIHelper: Retrying ChatGPT request (attempt " .. attempt .. ")")
        end

        local res, code, response_text, status = self:makeRequest(url, {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. config.api_key,
            ["Content-Length"] = tostring(#request_body),
        }, request_body, 300, 900) -- Connect timeout 300s, Total 900s
        
        local code_num = tonumber(code)
        logger.info("AIHelper: ChatGPT API Code:", code_num, "Length:", response_text and #response_text or 0)

        if code_num == 200 and response_text then
            local success, data = pcall(json.decode, response_text)
            if not success then 
                logger.warn("AIHelper: JSON parse error")
                return nil, "error_json_parse" 
            end
            
            -- CRASH PROTECTION: OpenAI response structure
            if data and data.choices and data.choices[1] then
                local choice = data.choices[1]
                
                -- Check finish reason
                if choice.finish_reason == "content_filter" then
                    logger.warn("AIHelper: BLOCKED BY CONTENT FILTER")
                    return nil, "error_safety", "Blocked by OpenAI Content Filter."
                end
                
                if choice.message and choice.message.content then
                    local content = choice.message.content
                    logger.info("AIHelper: ChatGPT response received, parsing...")
                    local result, err = self:parseAIResponse(content)
                    if result then
                        return result
                    else
                        return nil, "error_parse", err or "Failed to parse ChatGPT response."
                    end
                else
                    logger.warn("AIHelper: No content in ChatGPT response")
                    return nil, "error_api", "API returned empty response."
                end
            else
                -- Log error message if exists
                if data and data.error then
                    logger.warn("AIHelper: ChatGPT API Error:", data.error.message or "Unknown")
                    return nil, "error_api", data.error.message or "API Error"
                end
                return nil, "error_api", "Invalid response format"
            end
        elseif code == "USER_CANCELLED" then
            return nil, "USER_CANCELLED", "Request cancelled"
        elseif code == "error_timeout" then
            return nil, "error_timeout", "Connection timed out"
        elseif code_num == 429 then
            logger.warn("AIHelper: 429 Rate Limit (Retrying...)")
            -- Wait longer for rate limit
            if attempt <= max_retries then
                local socket = require("socket")
                socket.sleep(5)
            end
        elseif code_num == 503 or code_num == 502 then
            logger.warn("AIHelper: " .. code_num .. " Service Error (Retrying...)")
        elseif code_num == 401 then
            return nil, "error_401", "Invalid API key"
        else
            logger.warn("AIHelper: Unexpected error code:", code_num or code)
            return nil, "error_" .. tostring(code_num or code), "Error Code: " .. tostring(code_num or code)
        end
    end
    
    return nil, "error_timeout", "Timeout"
end

-- Helper to fix truncated JSON by closing open structures and removing partial entries
local function fixTruncatedJSON(s)
    if not s or #s == 0 then return s end

    local stack = {}
    local in_string = false
    local escaped = false

    -- 1. Identify nesting and strings
    for i = 1, #s do
        local c = s:sub(i,i)
        if escaped then
            escaped = false
        elseif c == "\\" then
            escaped = true
        elseif c == '"' then
            in_string = not in_string
        elseif not in_string then
            if c == "{" or c == "[" then
                table.insert(stack, c)
            elseif c == "}" then
                if #stack > 0 and stack[#stack] == "{" then table.remove(stack) end
            elseif c == "]" then
                if #stack > 0 and stack[#stack] == "[" then table.remove(stack) end
            end
        end
    end

    local res = s
    
    -- 2. Handle the tail
    if in_string then 
        -- Truncated inside a string value OR key
        res = res .. '"' 
    end

    -- Remove trailing garbage that isn't a complete value
    res = res:gsub("%s+$", "")
    
    -- Loop to strip partial trailing items (keys without values, trailing commas)
    local changed = true
    while changed do
        changed = false
        -- Remove trailing comma (invalid before closing brace/bracket)
        local n
        res, n = res:gsub(",%s*$", "")
        if n > 0 then changed = true end
        
        -- Remove trailing colon and its key (e.g., "key":)
        if res:match('"%s*:%s*$') then
            res = res:gsub('"%s*:[^"]*"%s*$', "") -- remove "key":
            res = res:gsub('"%s*:%s*$', "")       -- or just : if key was already closed
            changed = true
        end

        -- Remove a trailing key that was just closed by our quote fix above
        -- (e.g., ... , "partial_key" ) -> if it's inside an object { }
        if #stack > 0 and stack[#stack] == "{" and res:match('"%s*$') then
            -- If the last non-space char before this string is a comma or brace, 
            -- and there is no colon AFTER it, it's a partial key.
            -- Since we are at the end, if it's a string not followed by a colon, it's garbage.
            local before_string = res:gsub('"[^"]*"%s*$', "")
            if before_string:match("[,{]%s*$") then
                res = before_string
                changed = true
            end
        end
    end

    -- 3. Close all open structures in reverse order
    for i = #stack, 1, -1 do
        if stack[i] == "{" then
            res = res .. "}"
        elseif stack[i] == "[" then
            res = res .. "]"
        end
    end
    
    return res
end

function AIHelper:parseAIResponse(text)
    if not text or #text == 0 then
        return nil, "AI returned an empty response."
    end

    -- 1. Initial Cleaning (Remove ANY markdown blocks)
    local json_text = text:gsub("```%w*", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- 2. Try direct parse
    local success, data = pcall(json.decode, json_text)
    
    -- 3. If failed, extract ONLY the JSON part (from first {/[ to last }/])
    if not success then
        local first_brace = json_text:find("{", 1, true)
        local first_bracket = json_text:find("[", 1, true)
        local first = nil
        
        if first_brace and first_bracket then
            first = math.min(first_brace, first_bracket)
        else
            first = first_brace or first_bracket
        end

        if first then
             -- Find the last possible closing character
             local last_brace = json_text:reverse():find("}", 1, true)
             if last_brace then last_brace = #json_text - last_brace + 1 end
             
             local last_bracket = json_text:reverse():find("]", 1, true)
             if last_bracket then last_bracket = #json_text - last_bracket + 1 end
             
             local last = nil
             if last_brace and last_bracket then
                 last = math.max(last_brace, last_bracket)
             else
                 last = last_brace or last_bracket
             end

             local extracted = json_text:sub(first, last or #json_text)
             
             -- 4. If still invalid (truncated), try to fix it
             local fixed = fixTruncatedJSON(extracted)
             
             -- Try parsing with current json decoder
             success, data = pcall(json.decode, fixed)
             
             -- FALLBACK: If current decoder fails (likely rapidjson), try the standard Lua one
             if not success and rapidjson_ok then
                 local standard_json = require("json")
                 if standard_json and standard_json ~= json then
                     success, data = pcall(standard_json.decode, fixed)
                     if success then
                         logger.warn("AIHelper: JSON Parse succeeded using fallback decoder after repair.")
                     end
                 end
             end
             
             if success then
                 logger.warn("AIHelper: JSON Repair Succeeded. Data is partially recovered.")
             else
                 -- LOG ERROR FOR DEBUGGING - Show the last 500 chars of what we tried to fix
                 local fixed_snippet = fixed:sub(-500)
                 logger.warn("AIHelper: JSON Repair Failed. Last 500 chars of attempted fix: " .. fixed_snippet)
             end
        end
    end

    if success and data then
        return self:validateAndCleanData(data)
    end
    
    -- LOG ERROR FOR DEBUGGING
    local raw_snippet = text:sub(1, 1000)
    logger.warn("AIHelper: JSON Parse Failed. Raw start snippet: " .. raw_snippet)
    return nil, "Failed to parse AI response as JSON. The response may be invalid or truncated.\n\nCheck KOReader logs for 'AIHelper' to see technical details."
end

function AIHelper:validateAndCleanData(data)
    if not data then return nil end
    local strings = self:getFallbackStrings()
    
    local function ensureString(v, d)
        return (type(v) == "string" and #v > 0) and v or d or ""
    end

    -- 1. AUTHOR & BOOK (Smart Match)
    data.book_title = data.book_title or data.title or strings.unknown_book
    data.author = data.author or data.book_author or strings.unknown_author
    data.author_bio = ensureString(data.author_bio or data.AuthorBio or data.bio, "")
    data.author_birth = ensureString(data.author_birth, "---")
    data.author_death = ensureString(data.author_death, "---")
    data.summary = data.summary or data.book_summary or ""

    -- 2. CHARACTERS
    local chars = data.characters or data.Characters or {}
    local valid_chars = {}
    for _, c in ipairs(chars) do
        if type(c) == "table" then
            table.insert(valid_chars, {
                name = ensureString(c.name or c.Name, strings.unnamed_character),
                role = ensureString(c.role or c.Role, strings.not_specified),
                description = ensureString(c.description or c.desc, strings.no_description),
                gender = ensureString(c.gender, ""),
                occupation = ensureString(c.occupation, "")
            })
        end
    end
    data.characters = valid_chars

    -- 3. HISTORICAL FIGURES
    local hists = data.historical_figures or data.historicalFigures or {}
    local valid_hists = {}
    for _, h in ipairs(hists) do
        if type(h) == "table" then
            table.insert(valid_hists, {
                name = ensureString(h.name or h.Name, strings.unnamed_person),
                biography = ensureString(h.biography or h.bio, strings.no_biography),
                role = ensureString(h.role, ""),
                importance_in_book = ensureString(h.importance_in_book or h.importance, "Mentioned in book"),
                context_in_book = ensureString(h.context_in_book or h.context, "Historical reference")
            })
        end
    end
    data.historical_figures = valid_hists

    -- 4. OTHERS
    data.locations = data.locations or {}
    data.themes = data.themes or {}
    data.timeline = data.timeline or {}
    
    return data
end

function AIHelper:setAPIKey(provider, api_key)
    if self.providers[provider] then
        self.providers[provider].api_key = api_key:gsub("%s+", "")
        self:saveAPIKeyToFile(provider, api_key)
        return true
    end
    return false
end

function AIHelper:testAPIKey(provider)
    local provider_config = self.providers[provider]
    
    if not provider_config then
        return false, "Unknown provider"
    end
    
    if not provider_config.api_key or #provider_config.api_key == 0 then
        return false, "AI API Key not set"
    end
    
    logger.info("AIHelper: Testing", provider, "API key")
    
    local test_prompt = "Test: 'OK'"
    
    if provider == "gemini" then
        local result, error_code, error_msg = self:callGemini(test_prompt, provider_config)
        if result then
            return true, "Success"
        else
            return false, error_msg or ("Error: " .. (error_code or "Unknown"))
        end
        
    elseif provider == "chatgpt" then
        local result, error_code, error_msg = self:callChatGPT(test_prompt, provider_config)
        if result then
            return true, "Success"
        else
            return false, error_msg or ("Error: " .. (error_code or "Unknown"))
        end
    end
    
    return false, "Unsupported provider"
end

return AIHelper
