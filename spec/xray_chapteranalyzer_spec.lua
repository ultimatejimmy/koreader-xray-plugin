-- xray_chapteranalyzer_spec.lua
require("spec.spec_helper")
local analyzer = require("xray_chapteranalyzer")

describe("xray_chapteranalyzer", function()
    describe("countMentions", function()
        it("counts exact mentions correctly", function()
            local text = "Alice went to the park. Alice saw a bird."
            assert.are.equal(2, analyzer:countMentions(text, "Alice"))
        end)

        it("counts case-insensitive mentions", function()
            local text = "Alice went to the park. alice saw a bird."
            assert.are.equal(2, analyzer:countMentions(text, "Alice"))
        end)

        it("handles word boundaries for short names", function()
            -- Short names (< 4 chars) should respect word boundaries
            local text = "Jo went to Jordan's house. Jo is happy."
            -- "Jo" appears twice as a word. "Jordan" contains "Jo" but shouldn't count.
            assert.are.equal(2, analyzer:countMentions(text, "Jo"))
        end)
    end)

    describe("findCharactersInText", function()
        local chars = {
            { name = "Alice", id = 1 },
            { name = "Bob", id = 2 },
            { name = "Charlie", id = 3 }
        }

        it("finds present characters and sorts by count", function()
            local text = "Alice saw Bob. Bob waved at Alice. Bob is tall."
            local found = analyzer:findCharactersInText(text, chars)
            
            assert.are.equal(2, #found)
            assert.are.equal("Bob", found[1].character.name)
            assert.are.equal(3, found[1].count)
            assert.are.equal("Alice", found[2].character.name)
            assert.are.equal(2, found[2].count)
        end)

        it("handles first name matching", function()
            local chars_with_full_names = {
                { name = "Alice Liddell", id = 1 }
            }
            local text = "Alice went down the rabbit hole."
            local found = analyzer:findCharactersInText(text, chars_with_full_names)
            
            assert.are.equal(1, #found)
            assert.are.equal("Alice Liddell", found[1].character.name)
        end)
    end)
end)
