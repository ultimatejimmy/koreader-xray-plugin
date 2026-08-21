-- spec/xray_seriesmanager_spec.lua
require("spec.spec_helper")
local SeriesManager = require("xray_seriesmanager")
local xray_fetch = require("xray_fetch")

describe("xray_seriesmanager", function()
    local manager
    local test_slug = "the_wheel_of_time"
    local test_cache_path = "/tmp/koreader/settings/xray/series/" .. test_slug .. ".lua"

    before_each(function()
        manager = SeriesManager:new()
        -- Ensure clean caching directory
        os.execute("rm -rf /tmp/koreader")
        os.execute("mkdir -p /tmp/koreader/settings/xray/series")
    end)

    after_each(function()
        os.execute("rm -rf /tmp/koreader")
    end)

    describe("makeSlug", function()
        it("creates correct slug from series name", function()
            local props = { series = "The Wheel of Time", seriesindex = 3 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("the_wheel_of_time", info.slug)

            local props_punc = { series = "A Game... of Thrones!!", seriesindex = 1 }
            local info_punc = manager:detectSeries(props_punc)
            assert.are.equal("a_game_of_thrones", info_punc.slug)
        end)
    end)

    describe("detectSeries", function()
        it("detects series from EPUB props.series and props.seriesindex", function()
            local props = { series = "Mistborn", seriesindex = 2 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("Mistborn", info.name)
            assert.are.equal(2, info.index)
            assert.are.equal("mistborn", info.slug)
        end)

        it("detects series from EPUB props.Series and props.series_index", function()
            local props = { Series = "Stormlight Archive", series_index = 4 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("Stormlight Archive", info.name)
            assert.are.equal(4, info.index)
            assert.are.equal("stormlight_archive", info.slug)
        end)

        it("falls back to AI detection when metadata is missing", function()
            local mock_ai = {
                createPrompt = function(self, title, author, context, prompt_type)
                    assert.are.equal("The Way of Kings", title)
                    assert.are.equal("Brandon Sanderson", author)
                    assert.are.equal("series_detect", prompt_type)
                    return { type = "detect" }
                end,
                executeUnifiedRequest = function(self, prompt)
                    return {
                        is_series = true,
                        series_name = "The Stormlight Archive",
                        book_index = 1
                    }
                end
            }

            local info = manager:detectSeries({}, "The Way of Kings", "Brandon Sanderson", mock_ai)
            assert.is_not_nil(info)
            assert.are.equal("The Stormlight Archive", info.name)
            assert.are.equal(1, info.index)
            assert.are.equal("the_stormlight_archive", info.slug)
        end)

        it("returns nil if AI reports book is not part of a series", function()
            local mock_ai = {
                createPrompt = function() return {} end,
                executeUnifiedRequest = function()
                    return { is_series = false }
                end
            }
            local info = manager:detectSeries({}, "Standalone Book", "Author", mock_ai)
            assert.is_nil(info)
        end)
    end)

    describe("getPriorBookList", function()
        it("returns prior book list from AI", function()
            local series_info = { name = "Mistborn", index = 3, slug = "mistborn" }
            local mock_ai = {
                createPrompt = function(self, title, author, context, prompt_type)
                    assert.is_nil(title)
                    assert.are.equal("Brandon Sanderson", author)
                    assert.are.equal("Mistborn", context.series_name)
                    assert.are.equal(3, context.index)
                    assert.are.equal("prior_book_list", prompt_type)
                    return { type = "list" }
                end,
                executeUnifiedRequest = function(self, prompt)
                    return {
                        prior_books = {
                            { index = 1, title = "The Final Empire", author = "Brandon Sanderson" },
                            { index = 2, title = "The Well of Ascension", author = "Brandon Sanderson" }
                        }
                    }
                end
            }

            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", mock_ai)
            assert.are.equal(2, #list)
            assert.are.equal("The Final Empire", list[1].title)
            assert.are.equal(1, list[1].index)
            assert.are.equal("The Well of Ascension", list[2].title)
            assert.are.equal(2, list[2].index)
        end)

        it("generates fallback placeholders if AI helper is missing or returns nil", function()
            local series_info = { name = "Mistborn", index = 3, slug = "mistborn" }
            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", nil)
            assert.are.equal(2, #list)
            assert.are.equal("Mistborn (Book 1)", list[1].title)
            assert.are.equal("Brandon Sanderson", list[1].author)
            assert.are.equal("Mistborn (Book 2)", list[2].title)
        end)

        it("returns empty list if book index is 1", function()
            local series_info = { name = "Mistborn", index = 1, slug = "mistborn" }
            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", nil)
            assert.are.equal(0, #list)
        end)
    end)

    describe("caching", function()
        it("saves and loads series cache correctly", function()
            local test_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Kelsier", description = "Survivor of Hathsin" }
                        },
                        locations = {
                            { name = "Luthadel", description = "Capital city" }
                        }
                    }
                }
            }

            local saved = manager:saveSeriesCache(test_slug, test_data)
            assert.is_true(saved)

            local loaded = manager:loadSeriesCache(test_slug)
            assert.is_not_nil(loaded)
            assert.are.equal("6.0", loaded.cache_version)
            assert.is_not_nil(loaded.books[1])
            assert.are.equal("Kelsier", loaded.books[1].characters[1].name)
            assert.are.equal("Survivor of Hathsin", loaded.books[1].characters[1].description)
            assert.are.equal("Luthadel", loaded.books[1].locations[1].name)
        end)

        it("returns nil if loading non-existent slug", function()
            local loaded = manager:loadSeriesCache("nonexistent_slug")
            assert.is_nil(loaded)
        end)

        it("creates a series cache on first upsertBook", function()
            local ok = manager:upsertBook(test_slug, 1, {
                title = "Le Roi de fer",
                characters = { { name = "Philippe le Bel" } },
            }, "Les Rois Maudits")
            assert.is_true(ok)
            local loaded = manager:loadSeriesCache(test_slug)
            assert.is_not_nil(loaded)
            assert.are.equal("Les Rois Maudits", loaded.series_name)
            assert.are.equal("Le Roi de fer", loaded.books[1].title)
            assert.are.equal("Philippe le Bel", loaded.books[1].characters[1].name)
        end)
    end)

    describe("nearby sidecar matching", function()
        it("treats a Readest rename / dropped 02- prefix as the same volume", function()
            assert.is_true(manager:isSameVolume(
                "La Reine étranglée",
                "02 - La Reine étranglée - Readaloud"))
            assert.is_false(manager:isSameVolume("La Reine étranglée", "Le Roi de fer"))
        end)
            assert.is_true(manager:titlesMatch("Le Roi de fer", "le roi de fer"))
            assert.is_true(manager:titlesMatch("La Reine étranglée", "02 - La Reine etranglee - Readaloud"))
            assert.is_false(manager:titlesMatch("le", "le roi de fer"))
        end)

        it("picks a sibling sidecar by folder name when cache has no title field", function()
            local candidates = {
                { name = "Le Roi de fer.sdr", title = nil, author = "Maurice Druon\nLivraphone", data = { characters = { { name = "A" } } } },
                { name = "02 - La Reine étranglée - Readaloud.sdr", title = nil, author = "Maurice Druon", data = { characters = { { name = "B" } } } },
            }
            local picked = manager:selectNearbyPrior(
                "Le Roi de fer", "Maurice Druon",
                "02 - La Reine étranglée - Readaloud.sdr", candidates)
            assert.is_not_nil(picked)
            assert.are.equal("Le Roi de fer.sdr", picked.name)
        end)

        it("falls back to a unique same-author sibling", function()
            local candidates = {
                { name = "Le Roi de fer.sdr", title = nil, author = "Maurice Druon", data = {} },
                { name = "El buscapleitos.sdr", title = "El buscapleitos", author = "Jan Needle", data = {} },
            }
            local picked = manager:selectNearbyPrior(
                "Les Rois Maudits (Book 1)", "Maurice Druon",
                "02 - La Reine étranglée - Readaloud.sdr", candidates)
            assert.is_not_nil(picked)
            assert.are.equal("Le Roi de fer.sdr", picked.name)
        end)
    end)

    describe("volume index and canonical slug", function()
        it("does not invent index=1 when series metadata has no volume number", function()
            local info = manager:detectSeries({ series = "Rois Maudits" })
            assert.is_not_nil(info)
            assert.are.equal("Rois Maudits", info.name)
            assert.is_nil(info.index)
        end)

        it("reads volume index from a numbered filename", function()
            local info = manager:detectSeries(
                { series = "Rois Maudits" },
                "La Reine étranglée",
                "Maurice Druon",
                nil,
                "/sdcard/Books/02 - La Reine étranglée - Readaloud.epub"
            )
            assert.are.equal(2, info.index)
        end)

        it("parses calibre 1.0 series_index as 1", function()
            assert.are.equal(1, manager:parseIndex("1.0"))
            assert.are.equal(2, manager:parseIndex(2))
            assert.is_nil(manager:parseIndex(nil))
        end)

        it("maps Les Rois Maudits and Rois Maudits to the same slug", function()
            assert.are.equal("rois_maudits", manager:canonicalSlug("Les Rois Maudits"))
            assert.are.equal("rois_maudits", manager:canonicalSlug("Rois Maudits"))
            local a = manager:detectSeries({ series = "Les Rois Maudits", series_index = 1 })
            local b = manager:detectSeries({ series = "Rois Maudits", series_index = 2 })
            assert.are.equal(a.slug, b.slug)
            assert.are.equal("rois_maudits", a.slug)
        end)
    end)

    describe("mergeSeriesContext", function()
        local plugin

        before_each(function()
            plugin = createMockPlugin()
            for k, v in pairs(xray_fetch) do
                plugin[k] = v
            end
            plugin.cache_manager = {
                saveCache = function() return true end,
                asyncSaveCache = function() return true end,
                loadCache = function() return {} end
            }
        end)

        it("merges characters, locations, terms, and timeline events additively", function()
            plugin.characters = {
                { name = "Vin", description = "Street urchin" }
            }
            plugin.locations = {
                { name = "Luthadel", description = "Current city details" }
            }
            plugin.terms = {
                { name = "Allomancy", definition = "Current definition" }
            }
            plugin.timeline = {
                { chapter = "Chapter 1", event = "Current book event", page = 5 }
            }

            local cache_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Vin", description = "Survivor's apprentice" },
                            { name = "Kelsier", description = "The Survivor" }
                        },
                        locations = {
                            { name = "Luthadel", description = "Capital of Final Empire" },
                            { name = "Hathsin", description = "Pits of Hathsin" }
                        },
                        terms = {
                            { name = "Allomancy", definition = "Metal burning art" },
                            { name = "Feruchemy", definition = "Metal storing art" }
                        },
                        timeline = {
                            { chapter = "Prologue", event = "Kelsier destroys pits" }
                        }
                    }
                }
            }

            local series_info = { name = "Mistborn", index = 2, slug = "mistborn" }
            plugin:mergeSeriesContext(cache_data, series_info)

            -- Verify existing character is prepended with [From Book N]
            assert.are.equal(2, #plugin.characters)
            local vin = plugin.characters[1]
            assert.are.equal("Vin", vin.name)
            assert.truthy(vin.description:find("^%[From Book 1%] Survivor's apprentice"))
            assert.truthy(vin.description:find("Street urchin$"))

            -- Verify new character is inserted with source = series_prior
            local kelsier = plugin.characters[2]
            assert.are.equal("Kelsier", kelsier.name)
            assert.are.equal("series_prior", kelsier.source)
            assert.are.equal(1, kelsier.source_book)

            -- Verify locations merging
            assert.are.equal(2, #plugin.locations)
            local luthadel = plugin.locations[1]
            assert.truthy(luthadel.description:find("^%[From Book 1%] Capital of Final Empire"))
            local hathsin = plugin.locations[2]
            assert.are.equal("Hathsin", hathsin.name)
            assert.are.equal("series_prior", hathsin.source)

            -- Verify terms merging
            assert.are.equal(2, #plugin.terms)
            local allomancy = plugin.terms[1]
            assert.truthy(allomancy.definition:find("^%[From Book 1%] Metal burning art"))
            local feruchemy = plugin.terms[2]
            assert.are.equal("Feruchemy", feruchemy.name)
            assert.are.equal("series_prior", feruchemy.source)

            -- Verify timeline events: prior events should have source = series_prior, negative page
            -- (sortTimelineByTOC is a no-op in tests; search by source rather than assuming position)
            assert.are.equal(2, #plugin.timeline)
            local prior_ev = nil
            for _, ev in ipairs(plugin.timeline) do
                if ev.source == "series_prior" then prior_ev = ev; break end
            end
            assert.is_not_nil(prior_ev)
            assert.are.equal("[Book 1]", prior_ev.chapter)
            assert.are.equal("Kelsier destroys pits", prior_ev.event)
            assert.are.equal("series_prior", prior_ev.source)
            assert.are.equal(-999, prior_ev.page) -- -1000 + 1
        end)

        it("ensures re-runnability is clean and doesn't duplicate prefixes or list items", function()
            plugin.characters = {
                { name = "Vin", description = "Street urchin" }
            }
            local cache_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Vin", description = "Survivor's apprentice" },
                            { name = "Kelsier", description = "The Survivor" }
                        }
                    }
                }
            }
            local series_info = { name = "Mistborn", index = 2, slug = "mistborn" }

            -- Run merge once
            plugin:mergeSeriesContext(cache_data, series_info)
            assert.are.equal(2, #plugin.characters)

            -- Run merge a second time
            plugin:mergeSeriesContext(cache_data, series_info)

            -- Count of characters should remain 2 (prior Kelsier removed and re-added, not duplicated)
            assert.are.equal(2, #plugin.characters)
            local vin = plugin.characters[1]
            -- Description should contain prefix only once
            local count = 0
            for _ in vin.description:gmatch("%[From Book 1%]") do
                count = count + 1
            end
            assert.are.equal(1, count)
        end)
    end)
end)
