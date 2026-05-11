-- json_constraint_spec.lua
require("spec/spec_helper")

describe("OpenAI JSON Constraint", function()
    local AIHelper
    local json = require("json")

    setup(function()
        AIHelper = require("xray_aihelper")
        package.loaded["datastorage"] = {
            getSettingsDir = function() return "spec/mocks" end
        }
    end)

    before_each(function()
        AIHelper.settings = {}
        AIHelper.providers.chatgpt.api_key = "test_key"
        AIHelper.prompts = nil
    end)

    describe("buildComprehensiveRequest", function()
        it("should append 'json' sentinel when system instruction lacks 'json'", function()
            AIHelper.settings.primary_ai = { provider = "chatgpt", model = "gpt-4o-mini" }
            AIHelper.prompts = { system_instruction = "You are a literary researcher." } -- no 'json'
            
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local body = json.decode(requests[1].body)
            
            local system_message = ""
            for _, msg in ipairs(body.messages) do
                if msg.role == "system" or msg.role == "developer" then
                    system_message = msg.content
                end
            end
            
            assert.truthy(system_message:lower():find("json"))
            assert.are.equal("You are a literary researcher. Respond in JSON format.", system_message)
        end)

        it("should NOT append sentinel if 'json' is already present", function()
            AIHelper.settings.primary_ai = { provider = "chatgpt", model = "gpt-4o-mini" }
            AIHelper.prompts = { system_instruction = "Return valid JSON." }
            
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local body = json.decode(requests[1].body)
            
            local system_message = ""
            for _, msg in ipairs(body.messages) do
                if msg.role == "system" then
                    system_message = msg.content
                end
            end
            
            assert.are.equal("Return valid JSON.", system_message)
        end)
        
        it("should NOT append sentinel for reasoning models (where response_format is nil)", function()
            AIHelper.settings.primary_ai = { provider = "chatgpt", model = "gpt-5.4-mini" }
            AIHelper.settings.reasoning_effort = "low"
            AIHelper.prompts = { system_instruction = "You are a literary researcher." }
            
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local body = json.decode(requests[1].body)
            
            assert.is_nil(body.response_format)
            local system_message = body.messages[1].content
            -- For reasoning models, we append " You MUST output strictly valid JSON, starting with '{'."
            assert.truthy(system_message:find("strictly valid JSON"))
            assert.falsy(system_message:find("Respond in JSON format"))
        end)
    end)
end)
