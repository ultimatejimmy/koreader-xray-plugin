return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",
    
    -- Main prompt (Full book analysis)
    main = [[Book: "%s" - Author: %s
Create exhaustive X-Ray data for this book. Fill the JSON format COMPLETELY.

CORE RULES:
1. TARGET BOOK: Only include data from THIS book.
2. CHARACTERS: List 15-25 most important characters.
3. LOCATIONS: List 5-10 significant locations.
4. HISTORICAL FIGURES: Identify 3-7 real-world historical figures.
5. TIMELINE: 1 key highlight for EVERY chapter.
6. EXTREME BREVITY: Descriptions MUST be MAX 100-120 characters (1 short sentence). Timeline events MUST be MAX 80 characters.
7. COMPRESSION: Prioritize fitting within the 8,192 token limit. If space is tight, stop earlier.

REQUIRED JSON FORMAT:
{
  "book_title": "Full Book Title",
  "author": "Author Name",
  "summary": "Concise summary (max 250 chars).",
  "characters": [
    {
      "name": "Full Name",
      "role": "Role",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Short bio (MAX 120 chars)."
    }
  ],
  "historical_figures": [
    {
      "name": "Name",
      "role": "Role",
      "biography": "Short bio (MAX 120 chars)",
      "importance_in_book": "Significance",
      "context_in_book": "Context"
    }
  ],
  "locations": [
    {"name": "Place", "description": "Short desc (MAX 100 chars)", "importance": "Significance"}
  ],
  "themes": ["Theme 1", "Theme 2", "Theme 3"],
  "timeline": [
    {"event": "Key Event (MAX 80 chars)", "chapter": "Chapter", "importance": "High/Low"}
  ]
}]],

    -- Spoiler-free prompt (Based on reading progress)
    spoiler_free = [[Book: "%s" - Author: %s
CRITICAL: The reader has only read %d%% of this book. 

STRICT RULES:
1. NO SPOILERS: No info from after the %d%% mark.
2. TIMELINE: 1 key highlight for EVERY chapter up to %d%%.
3. EXTREME BREVITY: ALL descriptions/events MUST be MAX 100 characters.
4. COMPRESSION: Fit within 8,192 token limit.

ITEM COUNT REQUIREMENTS:
1. CHARACTERS: List 15-25 characters intro'd before %d%%.
2. LOCATIONS: List 5-10 locations mentioned.

REQUIRED JSON FORMAT:
{
  "book_title": "Book Title",
  "author": "Author Name",
  "summary": "Summary up to %d%% (max 250 chars).",
  "characters": [
    {
      "name": "Name",
      "role": "Role at %d%%",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Status at %d%% (MAX 100 chars)."
    }
  ],
  "historical_figures": [
    {
      "name": "Name",
      "role": "Role",
      "biography": "Short bio (MAX 100 chars)",
      "importance_in_book": "Significance at %d%%",
      "context_in_book": "Context"
    }
  ],
  "locations": [
    {"name": "Name", "description": "Desc at %d%% (MAX 100 chars).", "importance": "Significance"}
  ],
  "themes": ["Themes at %d%%"],
  "timeline": [
    {"event": "Key Event (MAX 80 chars)", "chapter": "Chapter", "importance": "High/Low"}
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
