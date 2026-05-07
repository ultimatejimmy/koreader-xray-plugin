-- xray_data_spec.lua
require("spec/spec_helper")

describe("xray_data", function()
    local xray_data

    setup(function()
        xray_data = require("xray_data")
    end)

    describe("normalizeChapterName", function()
        it("should handle digits", function()
            assert.are.equal("1", xray_data:normalizeChapterName("Chapter 1"))
            assert.are.equal("12", xray_data:normalizeChapterName("Ch. 12"))
        end)

        it("should handle written numbers", function()
            assert.are.equal("1", xray_data:normalizeChapterName("Chapter One"))
            assert.are.equal("20", xray_data:normalizeChapterName("Twenty"))
        end)

        it("should handle Roman numerals", function()
            assert.are.equal("4", xray_data:normalizeChapterName("IV"))
            assert.are.equal("9", xray_data:normalizeChapterName("Chapter IX"))
        end)

        it("should strip prefixes", function()
            assert.are.equal("intro", xray_data:normalizeChapterName("Chapter Intro"))
            assert.are.equal("prologue", xray_data:normalizeChapterName("Book Prologue"))
        end)
    end)

    describe("isNonNarrativeChapter", function()
        it("should identify non-narrative chapters", function()
            assert.is_true(xray_data:isNonNarrativeChapter("Table of Contents"))
            assert.is_true(xray_data:isNonNarrativeChapter("About the Author"))
            assert.is_true(xray_data:isNonNarrativeChapter("Cover"))
        end)

        it("should identify narrative chapters", function()
            assert.is_false(xray_data:isNonNarrativeChapter("Chapter 1"))
            assert.is_false(xray_data:isNonNarrativeChapter("The Journey Begins"))
        end)
    end)

    describe("isMoreCompleteName", function()
        it("should return true if new name contains old name", function()
            assert.is_true(xray_data:isMoreCompleteName("John Watson", "Watson"))
            assert.is_true(xray_data:isMoreCompleteName("Dr. John Watson", "John Watson"))
        end)

        it("should return false if names are unrelated", function()
            assert.is_false(xray_data:isMoreCompleteName("Sherlock", "Watson"))
        end)
    end)

    describe("deduplicateByName", function()
        it("should merge aliases and promote names", function()
            local list = {
                { name = "John Watson", aliases = {"Watson"} },
                { name = "Watson", aliases = {"Doctor"} }
            }
            local result = xray_data:deduplicateByName(list, "name")
            assert.are.equal(1, #result)
            assert.are.equal("John Watson", result[1].name)
            local aliases = {}
            for _, a in ipairs(result[1].aliases) do aliases[a:lower()] = true end
            assert.is_true(aliases["doctor"])
            assert.is_true(aliases["watson"])
        end)
    end)

    describe("assignTimelinePages", function()
        it("should match by exact name", function()
            local timeline = { { chapter = "Chapter 1" } }
            local toc = { { title = "Chapter 1", page = 5 } }
            xray_data:assignTimelinePages(timeline, toc)
            assert.are.equal(5, timeline[1].page)
        end)

        it("should match by leading number", function()
            local timeline = { { chapter = "1" } }
            local toc = { { title = "Chapter 1: The Start", page = 10 } }
            xray_data:assignTimelinePages(timeline, toc)
            assert.are.equal(10, timeline[1].page)
        end)

        it("should match multiple chapters with same number to sequential TOC entries", function()
            local timeline = { 
                { chapter = "1.1" },
                { chapter = "1.2" }
            }
            local toc = { 
                { title = "Chapter 1 Part 1", page = 10 },
                { title = "Chapter 1 Part 2", page = 20 }
            }
            xray_data:assignTimelinePages(timeline, toc)
            assert.are.equal(10, timeline[1].page)
            assert.are.equal(20, timeline[2].page)
        end)
    end)

    describe("sortDataByFrequency", function()
        it("should rank protagonists higher", function()
            local list = {
                { name = "Sidekick", role = "Supporting" },
                { name = "Hero", role = "Protagonist" }
            }
            xray_data:sortDataByFrequency(list, "Hero Hero Sidekick", "name")
            assert.are.equal("Hero", list[1].name)
        end)

        it("should rank by frequency when roles are same", function()
            local list = {
                { name = "Rare", role = "Minor" },
                { name = "Frequent", role = "Minor" }
            }
            -- Use high enough counts to overcome normalization
            xray_data:sortDataByFrequency(list, "Frequent Frequent Frequent Frequent Frequent Frequent Rare", "name")
            assert.are.equal("Frequent", list[1].name)
        end)
    end)
end)
