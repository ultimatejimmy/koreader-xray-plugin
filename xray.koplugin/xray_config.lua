-- X-Ray API Configuration

return {
    -- Google Gemini API Key
    -- To get an API key: https://makersuite.google.com/app/apikey
    -- Enter your API key here:
    gemini_api_key = "", 
    
    -- ChatGPT API Key 
    -- To get an API key: https://platform.openai.com/api-keys
    -- Enter your API key here:
    chatgpt_api_key = "",  

    -- DeepSeek API Key
    -- To get an API key: https://platform.deepseek.com/api_keys
    -- Enter your API key here:
    deepseek_api_key = "",

    -- Anthropic Claude API Key
    -- To get an API key: https://console.anthropic.com/settings/keys
    -- Enter your API key here:
    claude_api_key = "",

    -- Custom API slot 1 (e.g., OpenRouter, any OpenAI-compatible endpoint)
    custom1_api_key  = "",   -- Your API key for this endpoint
    custom1_endpoint = "",   -- e.g., "https://openrouter.ai/api/v1/chat/completions"
    custom1_model    = "",   -- e.g., "google/gemini-2.5-flash-preview-05-20"

    -- Custom API slot 2 (e.g., a local Ollama server)
    custom2_api_key  = "",
    custom2_endpoint = "",   -- e.g., "http://localhost:11434/v1/chat/completions"
    custom2_model    = "",   -- e.g., "llama3"
}
