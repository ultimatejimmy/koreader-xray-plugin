-- X-Ray API Configuration

return {
    -- Google Gemini API Key
    -- To get an API key: https://makersuite.google.com/app/apikey
    -- Enter your API key here:
    gemini_api_key = "XXXXXX", 
    
    -- Gemini Model Selection
    gemini_primary_model = "gemini-2.5-flash",
    gemini_secondary_model = "gemini-2.5-flash-lite",
    
    -- ChatGPT API Key 
    -- To get an API key: https://platform.openai.com/api-keys
    -- Enter your API key here:
    chatgpt_api_key = "sk-XXXX",  
    
    -- Default AI Provider
    default_provider = "gemini",
    
    -- Settings
    settings = {
        auto_fetch_on_open = false,  -- Automatically fetch data when a book is opened?
        cache_duration_days = -1,    -- Cache is valid indefinitely! 
        max_characters = 20,         -- Maximum number of characters to show?
    }
}
