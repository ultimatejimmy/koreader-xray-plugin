-- X-Ray API Configuration

return {
    -- Google Gemini API Key
    -- To get an API key: https://makersuite.google.com/app/apikey
    gemini_api_key = "AIzaSy----",  -- Enter your API key here: "AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    
    -- Gemini Model Selection
    gemini_primary_model = "gemini-2.5-flash",
    gemini_secondary_model = "gemini-2.5-flash-lite",
    
    -- ChatGPT API Key 
    -- To get an API key: https://platform.openai.com/api-keys
    chatgpt_api_key = "sk-XXXX",  -- Enter your API key here: "sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    
    -- Default AI Provider
    default_provider = "gemini",
    
    -- Settings
    settings = {
        auto_fetch_on_open = false,  -- Automatically fetch data when a book is opened?
        cache_duration_days = -1,    -- Cache is valid indefinitely! 
        max_characters = 20,         -- Maximum number of characters to show?
    }
}
