return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",
    
    -- Main prompt (Full book analysis)
    main = [[Book: "%s" - Author: %s
Create exhaustive X-Ray data for this book.

CORE RULES:
1. TARGET BOOK: Only include data from THIS book.
2. CHARACTERS: List 15-25 most important characters.
3. LOCATIONS: List 5-10 significant locations.
4. HISTORICAL FIGURES: Identify 3-7 real-world historical figures.
5. TIMELINE: 1 key highlight for EVERY narrative chapter. IGNORE Frontmatter, Table of Contents, "Also by", or Appendices.
6. CHARACTER DEPTH: Descriptions MUST be 250-300 characters. Provide a comprehensive analysis of the character's history and role throughout the entire book.
7. CONCISENESS: Other descriptions (locations/historical) MUST be MAX 150 characters.

REQUIRED JSON FORMAT:
{
  "book_title": "Full Book Title",
  "author": "Author Name",
  "characters": [
    {
      "name": "Full Name",
      "role": "Role",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Comprehensive analysis (250-300 characters). Encompass their full history in the book."
    }
  ],
  "historical_figures": [
    {
      "name": "Name",
      "role": "Role",
      "biography": "Short bio (MAX 150 chars)",
      "importance_in_book": "Significance",
      "context_in_book": "Context"
    }
  ],
  "locations": [
    {"name": "Place", "description": "Short desc (MAX 150 chars)", "importance": "Significance"}
  ],
  "timeline": [
    {"event": "Key narrative event (MAX 120 chars)", "chapter": "Chapter Name/Number", "importance": "High/Low"}
  ]
}]],

    -- Spoiler-free prompt (Based on reading progress)
    spoiler_free = [[Book: "%s" - Author: %s
CRITICAL: The reader has only read %d%% of this book. 

STRICT RULES:
1. NO SPOILERS: No info from after the %d%% mark.
2. TIMELINE: 1 key highlight for EVERY narrative chapter up to %d%%. IGNORE ToC/Frontmatter.
3. CHARACTER DEPTH: Descriptions MUST be 250-300 characters. Encompass their full history up to %d%%.
4. COMPRESSION: Fit within 8,192 token limit.

ITEM COUNT REQUIREMENTS:
1. CHARACTERS: List 15-25 characters intro'd before %d%%.
2. LOCATIONS: List 5-10 locations mentioned.

REQUIRED JSON FORMAT:
{
  "book_title": "Book Title",
  "author": "Author Name",
  "characters": [
    {
      "name": "Name",
      "role": "Role at %d%%",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Comprehensive history/status at %d%% (250-300 chars). NO SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Name",
      "role": "Role",
      "biography": "Short bio (MAX 150 chars)",
      "importance_in_book": "Significance at %d%%",
      "context_in_book": "Context"
    }
  ],
  "locations": [
    {"name": "Name", "description": "Desc at %d%% (MAX 150 chars).", "importance": "Significance"}
  ],
  "timeline": [
    {"event": "Key narrative event (MAX 120 chars)", "chapter": "Chapter", "importance": "High/Low"}
  ]
}]],

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identify and provide biography for the author of the book "%s". 
Metadata suggests the author is "%s", but verify this based on the book title.

REQUIRED JSON FORMAT:
{
  "author": "Correct Full Name",
  "author_bio": "Comprehensive biography focusing on their literary career and major works.",
  "author_birth": "Birth Date",
  "author_death": "Death Date"
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Unknown Book",
        unknown_author = "Unknown Author",
        unnamed_character = "Unnamed Character",
        not_specified = "Not Specified",
        no_description = "No Description",
        unnamed_person = "Unnamed Person",
        no_biography = "No Biography Available"
    }
}
