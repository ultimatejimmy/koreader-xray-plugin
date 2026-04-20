-- ChapterAnalyzer - Analyze which characters appear in current chapter/page
local logger = require("logger")
local AIHelper = require("xray_aihelper")

local ChapterAnalyzer = {}

function ChapterAnalyzer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Get current chapter/section text
function ChapterAnalyzer:getCurrentChapterText(ui)
    if not ui or not ui.document then
        logger.warn("ChapterAnalyzer: No document available")
        AIHelper:log("ChapterAnalyzer: No document available")
        return nil
    end
    
    -- Check if it's a reflowable document (EPUB, etc.) or page-based (PDF, etc.)
    local is_reflowable = ui.rolling ~= nil
    local is_paged = ui.paging ~= nil
    
    logger.info("ChapterAnalyzer: Reflowable:", is_reflowable, "Paged:", is_paged)
    AIHelper:log("ChapterAnalyzer: Reflowable: " .. tostring(is_reflowable) .. " Paged: " .. tostring(is_paged))
    
    if is_reflowable then
        return self:getReflowableText(ui)
    elseif is_paged then
        return self:getPageBasedText(ui)
    else
        logger.warn("ChapterAnalyzer: Unknown document type")
        AIHelper:log("ChapterAnalyzer: Unknown document type")
        return self:getFallbackText(ui)
    end
end

-- Get text from reflowable documents (EPUB, HTML, FB2)
function ChapterAnalyzer:getReflowableText(ui)
    -- Get current position - different methods for different versions
    local current_pos = nil
    
    -- Try different methods to get current position
    if ui.rolling.current_page then
        current_pos = ui.rolling.current_page
    elseif ui.rolling.getCurrentPos then
        current_pos = ui.rolling:getCurrentPos()
    elseif ui.document.getCurrentPos then
        current_pos = ui.document:getCurrentPos()
    elseif ui.view and ui.view.state and ui.view.state.page then
        current_pos = ui.view.state.page
    else
        -- Last resort: use page 1
        current_pos = 1
    end
    
    logger.info("ChapterAnalyzer: Current position:", current_pos)
    
    -- Try to get chapter from TOC
    local toc = ui.document:getToc()
    local default_chapter_title = ui.loc and ui.loc:t("this_chapter") or "This Chapter"
    if not toc or #toc == 0 then
        logger.info("ChapterAnalyzer: No TOC, using visible text")
        return self:getVisibleTextReflowable(ui), default_chapter_title
    end
    
    -- Find current chapter
    local current_chapter = nil
    local chapter_title = default_chapter_title
    
    for i, chapter in ipairs(toc) do
        if chapter.page <= current_pos then
            current_chapter = chapter
            chapter_title = chapter.title or default_chapter_title
        else
            break
        end
    end
    
    if not current_chapter then
        logger.warn("ChapterAnalyzer: No current chapter found")
        return self:getVisibleTextReflowable(ui), default_chapter_title
    end
    
    logger.info("ChapterAnalyzer: Current chapter:", chapter_title)
    
    -- For EPUB, we'll try to get text from the document
    -- Method 1: Try getTextFromPositions if available
    local text = ""
    local text_length = 50000  -- ~50k characters
    
    if ui.document.getTextFromPositions then
        local success, result = pcall(function()
            return ui.document:getTextFromPositions(current_pos, current_pos + text_length)
        end)
        
        if success and result and #result > 100 then
            text = result
            logger.info("ChapterAnalyzer: Got", #text, "characters from positions")
            return text, chapter_title
        end
    end
    
    -- Method 2: Try to extract text from current chapter xpointer
    if ui.document.getTextFromXPointer and current_chapter.xpointer then
        local success, result = pcall(function()
            return ui.document:getTextFromXPointer(current_chapter.xpointer)
        end)
        
        if success and result and #result > 100 then
            text = result
            logger.info("ChapterAnalyzer: Got", #text, "characters from xpointer")
            return text, chapter_title
        end
    end
    
    -- Method 3: Get visible text (fallback)
    text = self:getVisibleTextReflowable(ui)
    logger.info("ChapterAnalyzer: Using visible text fallback")
    
    return text, chapter_title
end

-- Get currently visible text (reflowable)
function ChapterAnalyzer:getVisibleTextReflowable(ui)
    -- Try multiple methods to get text
    local text = ""
    
    -- Method 1: Try getting text from view
    if ui.view and ui.view.document and ui.view.document.extractText then
        local success, result = pcall(function()
            return ui.view.document:extractText()
        end)
        if success and result and #result > 100 then
            logger.info("ChapterAnalyzer: Got text from view.document.extractText")
            return result
        end
    end
    
    -- Method 2: Try document getFullText
    if ui.document.getFullText then
        local success, result = pcall(function()
            return ui.document:getFullText()
        end)
        if success and result and #result > 100 then
            logger.info("ChapterAnalyzer: Got text from getFullText")
            -- Limit size
            if #result > 100000 then
                result = string.sub(result, 1, 100000)
            end
            return result
        end
    end
    
    -- Method 3: Try to read from pages (if document has pages)
    if ui.document.getPageCount and ui.document.getPageText then
        local page_count = ui.document:getPageCount()
        local max_pages = math.min(page_count, 50)
        
        for i = 1, max_pages do
            local success, page_text = pcall(function()
                return ui.document:getPageText(i)
            end)
            if success and page_text then
                text = text .. " " .. page_text
            end
        end
        
        if #text > 100 then
            logger.info("ChapterAnalyzer: Got text from pages")
            return text
        end
    end
    
    -- If nothing worked, return empty
    logger.warn("ChapterAnalyzer: Could not extract any text")
    return ""
end

-- Get text from page-based documents (PDF, DJVU)
function ChapterAnalyzer:getPageBasedText(ui)
    -- Try to get chapter from TOC
    local toc = ui.document:getToc()
    if not toc or #toc == 0 then
        logger.info("ChapterAnalyzer: No TOC, using current page only")
        return self:getCurrentPageTextPDF(ui)
    end
    
    -- Find current chapter based on page
    local current_page = ui.paging:getCurrentPage()
    local current_chapter = nil
    local next_chapter = nil
    
    for i, chapter in ipairs(toc) do
        if chapter.page <= current_page then
            current_chapter = chapter
            if i < #toc then
                next_chapter = toc[i + 1]
            end
        else
            break
        end
    end
    
    if not current_chapter then
        logger.warn("ChapterAnalyzer: No current chapter found")
        return self:getCurrentPageTextPDF(ui)
    end
    
    logger.info("ChapterAnalyzer: Current chapter:", current_chapter.title)
    
    -- Get text from current chapter start to next chapter start (or end)
    local start_page = current_chapter.page
    local end_page = next_chapter and next_chapter.page - 1 or ui.document:getPageCount()
    
    -- Limit to reasonable range (max 50 pages for performance)
    if end_page - start_page > 50 then
        end_page = start_page + 50
        logger.info("ChapterAnalyzer: Limited to 50 pages for performance")
    end
    
    logger.info("ChapterAnalyzer: Analyzing pages", start_page, "to", end_page)
    
    -- Collect text from pages
    local chapter_text = ""
    for page = start_page, end_page do
        local page_text = ui.document:getPageText(page)
        if page_text then
            chapter_text = chapter_text .. " " .. page_text
        end
    end
    
    return chapter_text, current_chapter.title
end

-- Get current page text (PDF/page-based) - fallback
function ChapterAnalyzer:getCurrentPageTextPDF(ui)
    local current_page = ui.paging:getCurrentPage()
    
    -- Try to get text from current page and next few pages
    local text = ""
    for i = 0, 4 do  -- Current + 4 pages
        local page = current_page + i
        if page <= ui.document:getPageCount() then
            local page_text = ui.document:getPageText(page)
            if page_text then
                text = text .. " " .. page_text
            end
        end
    end
    
    local default_page_title = ui.loc and ui.loc:t("this_page") or "This Page"
    return text, default_page_title
end

-- Fallback for unknown document types
function ChapterAnalyzer:getFallbackText(ui)
    logger.warn("ChapterAnalyzer: Using fallback text extraction")
    
    -- Try different methods
    local text = ""
    
    -- Method 1: Try to get selection text or visible text
    if ui.highlight and ui.highlight.selected_text then
        text = ui.highlight.selected_text.text or ""
    end
    
    -- Method 2: Try document getTextFromPositions if available
    if #text < 100 and ui.document.getTextFromPositions then
        local success, result = pcall(function()
            return ui.document:getTextFromPositions(0, 10000)
        end)
        if success and result then
            text = result
        end
    end
    
    -- Method 3: Just show a message
    if #text < 100 then
        logger.warn("ChapterAnalyzer: Could not extract text")
        return nil, nil
    end
    
    local default_page_title = ui.loc and ui.loc:t("this_page") or "This Page"
    return text, default_page_title
end

-- Find characters mentioned in text
function ChapterAnalyzer:findCharactersInText(text, characters)
    if not text or not characters then
        return {}
    end
    
    local found_characters = {}
    local text_lower = string.lower(text)
    
    for _, char in ipairs(characters) do
        local name = char.name
        if name and #name > 2 then
            -- Check full name
            local name_lower = string.lower(name)
            if string.find(text_lower, name_lower, 1, true) then
                table.insert(found_characters, {
                    character = char,
                    count = self:countMentions(text_lower, name_lower)
                })
            else
                -- Check first name only
                local first_name = string.match(name, "^(%S+)")
                if first_name and #first_name > 2 then
                    local first_name_lower = string.lower(first_name)
                    if string.find(text_lower, first_name_lower, 1, true) then
                        table.insert(found_characters, {
                            character = char,
                            count = self:countMentions(text_lower, first_name_lower)
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by mention count
    table.sort(found_characters, function(a, b)
        return a.count > b.count
    end)
    
    logger.info("ChapterAnalyzer: Found", #found_characters, "characters in text")
    AIHelper:log("ChapterAnalyzer: Found " .. tostring(#found_characters) .. " characters in text")
    
    return found_characters
end

-- Get text for analysis (up to max_len characters before current position)
function ChapterAnalyzer:getTextForAnalysis(ui, max_len, progress_callback, current_page, start_page)
    if not ui or not ui.document then
        AIHelper:log("ChapterAnalyzer: getTextForAnalysis - no document")
        return nil
    end
    
    max_len = max_len or 100000 
    local book_text = ""
    AIHelper:log("ChapterAnalyzer: Extracting text for analysis (max " .. tostring(max_len) .. " chars)")
    
    -- Check if it's a reflowable document (EPUB, etc.)
    local is_reflowable = ui.rolling ~= nil
    
    if is_reflowable then
        local current_xp = ui.document:getXPointer()
        if not current_xp then 
            AIHelper:log("ChapterAnalyzer: getTextForAnalysis - could not get XPointer")
            return nil 
        end
        
        -- Optimization: Adopt "extract from start" approach which is faster in creengine
        -- than seeking to arbitrary positions which might trigger re-pagination.
        local success, result = pcall(function()
            if progress_callback then progress_callback(0.1) end
            
            if start_page and start_page > 1 then
                -- Seek to start_page to get the incremental start XPointer
                AIHelper:log("ChapterAnalyzer: getTextForAnalysis - incremental mode from page " .. tostring(start_page))
                ui.document:gotoPage(start_page)
            else
                -- Go to the very beginning of the book (instant)
                ui.document:gotoPos(0)
            end
            local start_xp = ui.document:getXPointer()
            
            -- Go back to current position
            ui.document:gotoXPointer(current_xp)
            
            if progress_callback then progress_callback(0.3) end
            
            -- Extract EVERYTHING from start to here
            local full_text = ui.document:getTextFromXPointers(start_xp, current_xp) or ""
            
            -- Trim to the last max_len characters
            if #full_text > max_len then
                return full_text:sub(-max_len)
            else
                return full_text
            end
        end)
        
        if success and result then
            book_text = result
        else
            AIHelper:log("ChapterAnalyzer: getTextForAnalysis - XPointer extraction failed")
            -- Last ditch fallback
            book_text = ""
        end
    else
        -- For page-based documents (PDF), get text from a limited number of pages before current
        local current_pos = current_page or (ui.view and ui.view.state and ui.view.state.page) or 1
        local max_pages = 100 
        local calc_start_page = math.max(1, current_pos - max_pages)
        if start_page and start_page > 1 then
            calc_start_page = math.max(start_page, calc_start_page)
        end
        
        logger.info("ChapterAnalyzer: Extracting PDF pages", calc_start_page, "to", current_pos)
        AIHelper:log("ChapterAnalyzer: Extracting PDF pages " .. tostring(calc_start_page) .. " to " .. tostring(current_pos))
        
        for page = calc_start_page, current_pos do
            if progress_callback and (page % 10 == 0) and current_pos > calc_start_page then
                progress_callback(0.1 + (0.8 * (page - calc_start_page) / (current_pos - calc_start_page)))
            end
            
            local page_text = ui.document:getPageText(page) or ""
            if type(page_text) == "table" then
                local texts = {}
                for _, block in ipairs(page_text) do
                    if type(block) == "table" then
                        for i = 1, #block do
                            local span = block[i]
                            if type(span) == "table" and span.word then
                                table.insert(texts, span.word)
                            end
                        end
                    end
                end
                page_text = table.concat(texts, " ")
            end
            book_text = book_text .. page_text .. "\n"
        end
    end
    
    -- Limit text length (from the end)
    if #book_text > max_len then
        book_text = book_text:sub(-max_len)
    end
    
    if progress_callback then progress_callback(1.0) end
    logger.info("ChapterAnalyzer: Total characters extracted for analysis:", #book_text)
    AIHelper:log("ChapterAnalyzer: Total characters extracted for analysis: " .. tostring(#book_text))
    return book_text
end

-- Get highlights and notes for analysis
function ChapterAnalyzer:getAnnotationsForAnalysis(ui)
    local annotations_text = ""
    
    -- Try to get annotations from the document/UI
    -- In KOReader, annotations are typically in ui.annotation.annotations
    if ui.annotation and ui.annotation.annotations then
        for _, annot in ipairs(ui.annotation.annotations) do
            if annot.text and #annot.text > 0 then
                annotations_text = annotations_text .. "Highlight: " .. annot.text .. "\n"
            end
            if annot.note and #annot.note > 0 then
                annotations_text = annotations_text .. "Note: " .. annot.note .. "\n"
            end
        end
    end
    
    return #annotations_text > 0 and annotations_text or nil
end

-- Get detailed samples (Start/Mid/End) from each chapter
function ChapterAnalyzer:getDetailedChapterSamples(ui, max_chapters, total_limit, is_full_book, start_page)
    if not ui or not ui.document then return nil, nil end
    
    local toc = ui.document:getToc()
    if not toc or #toc == 0 then 
        logger.info("ChapterAnalyzer: No TOC found for detailed sampling")
        return nil, nil 
    end
    
    local current_page = nil
    if not is_full_book then
        if ui.view and ui.view.state and ui.view.state.page then
            current_page = ui.view.state.page
        elseif ui.rolling and ui.rolling.current_page then
            current_page = ui.rolling.current_page
        elseif ui.paging and ui.paging.getCurrentPage then
            current_page = ui.paging:getCurrentPage()
        end
    end
    
    max_chapters = max_chapters or 200
    total_limit = total_limit or 150000
    
    -- Non-narrative TOC entries to exclude
    local non_narrative_patterns = {
        "^cover$", "^title", "^copyright", "^table of contents", "^contents$",
        "^dedication", "^acknowledgment", "^also by", "^about the author",
        "^epilogue$", "^epigraph$", "^foreword$", "^preface$", "^introduction$",
        "^appendix", "^glossary", "^index$", "^notes$", "^bibliography",
        "^colophon", "^frontispiece",
    }
    local function isNonNarrative(title)
        if not title then return false end
        local lower = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
        for _, pat in ipairs(non_narrative_patterns) do
            if lower:match(pat) then return true end
        end
        return false
    end

    -- Filter chapters
    local active_chapters = {}
    local chapter_titles = {}
    for i, chapter in ipairs(toc) do
        if not is_full_book and current_page and chapter.page and chapter.page > current_page then
            break
        end
        
        -- Skip non-narrative chapters
        if isNonNarrative(chapter.title) then
            AIHelper:log("ChapterAnalyzer: Skipping non-narrative chapter: " .. (chapter.title or tostring(i)))
        else
            local skip = false
            if start_page and not is_full_book then
                local next_chapter_page = toc[i+1] and toc[i+1].page or math.huge
                if next_chapter_page <= start_page then
                    skip = true
                end
            end
            
            if not skip then
                if #active_chapters >= max_chapters then break end
                table.insert(active_chapters, chapter)
                table.insert(chapter_titles, chapter.title or tostring(i))
            else
                AIHelper:log("ChapterAnalyzer: Skipping already-fetched chapter: " .. (chapter.title or tostring(i)))
            end
        end
    end
    
    if #active_chapters == 0 then return nil, nil end
    
    -- Calculate budget per chapter
    -- Reserve 20k for the main book_text (last 20k)
    local chapter_total_budget = total_limit - 20000
    local per_chapter_budget = math.floor(chapter_total_budget / #active_chapters)
    
    -- Hard limit of 3600 per chapter as requested
    if per_chapter_budget > 3600 then per_chapter_budget = 3600 end
    
    -- Minimum budget for it to be useful
    if per_chapter_budget < 300 then per_chapter_budget = 300 end
    
    local sample_len = math.floor(per_chapter_budget / 3)
    local samples = {}
    
    logger.info("ChapterAnalyzer: Detailed sampling for", #active_chapters, "chapters. Budget per chapter:", per_chapter_budget)
    AIHelper:log("ChapterAnalyzer: Sampling " .. #active_chapters .. " chapters with " .. per_chapter_budget .. " chars each.")
    
    for i, chapter in ipairs(active_chapters) do
        local success, chapter_text = pcall(function()
            if ui.document.getTextFromXPointer and chapter.xpointer then
                -- EPUB: Usually returns the full text of the chapter file
                return ui.document:getTextFromXPointer(chapter.xpointer)
            end
            return ""
        end)
        
        if success and chapter_text and #chapter_text > 100 then
            local start_txt = chapter_text:sub(1, sample_len)
            local mid_start = math.max(1, math.floor(#chapter_text / 2) - math.floor(sample_len / 2))
            local mid_txt = chapter_text:sub(mid_start, mid_start + sample_len)
            local end_txt = chapter_text:sub(-sample_len)
            
            table.insert(samples, string.format(
                "CHAPTER [%s]:\n[START]: %s\n[MID]: %s\n[END]: %s",
                chapter.title or tostring(i),
                start_txt, mid_txt, end_txt
            ))
        end
    end
    
    return (#samples > 0 and table.concat(samples, "\n\n---\n\n") or nil), chapter_titles
end

function ChapterAnalyzer:countMentions(text, name)
    local count = 0
    local pos = 1
    
    while true do
        local start_pos = string.find(text, name, pos, true)
        if not start_pos then break end
        count = count + 1
        pos = start_pos + 1
    end
    
    return count
end

return ChapterAnalyzer
