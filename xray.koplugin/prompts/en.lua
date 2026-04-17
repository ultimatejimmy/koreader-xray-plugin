return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",
    
    -- Specialized section for Characters and Historical Figures
    character_section = [[Book: "%s" - Author: %s
Reading Progress: %d%%

TASK: List 15-25 most important characters and 3-7 real-world historical figures.

STRICT RULES:
1. FORMAL NAMES: Use the character's full formal name (e.g., "Abraham Van Helsing" instead of "the Professor"). Only use nicknames if no formal name exists.
2. HISTORICAL FIGURES: You MUST identify real-world people mentioned (authors, kings, scientists, etc.).
3. CHARACTER DEPTH: Provide a comprehensive analysis (250-300 characters). Encompass their full history and role throughout the whole book up to the %d%% mark.
4. NO SPOILERS: ABSOLUTELY NO information from after the %d%% mark.

REQUIRED JSON FORMAT:
{
  "characters": [
    {
      "name": "Full Formal Name",
      "role": "Role at %d%%",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Comprehensive history/analysis (250-300 chars). NO SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Full Name",
      "role": "Historical Role",
      "biography": "Short bio (MAX 150 chars)",
      "importance_in_book": "Significance at %d%%",
      "context_in_book": "Context"
    }
  ]
}]],

    -- Specialized section for Locations
    location_section = [[Book: "%s" - Author: %s
Reading Progress: %d%%

TASK: List 5-10 significant locations visited or mentioned up to the %d%% mark. 
SCAN FOR: City names, specific buildings, landmarks, or even recurring rooms.

RULES:
1. NO SPOILERS: Do not mention locations or events that occur after the %d%% mark.
2. CONCISENESS: Descriptions must be MAX 150 characters.

REQUIRED JSON FORMAT:
{
  "locations": [
    {"name": "Place", "description": "Short desc (MAX 150 chars)", "importance": "Significance at %d%%"}
  ]
}]],

    -- Specialized section for Timeline
    timeline_section = [[Book: "%s" - Author: %s
Reading Progress: %d%%

TASK: Create a chronological timeline of key narrative events up to the %d%% mark.

RULES:
1. COVERAGE: Provide 1 key highlight for EVERY narrative chapter up to the %d%% mark.
2. EXCLUSION: IGNORE Frontmatter, Table of Contents, "Also by", or Appendices.
3. BREVITY: Each event description MUST be MAX 120 characters.
4. NO SPOILERS: Stop exactly at the %d%% mark.

REQUIRED JSON FORMAT:
{
  "timeline": [
    {"event": "Key narrative event (MAX 120 chars)", "chapter": "Chapter Name/Number", "importance": "High/Low"}
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

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Book: "%s" - Author: %s
Reading Progress: %d%%

TASK: Provide a comprehensive X-Ray analysis of the book up to the %d%% mark.

1. CHARACTERS & FIGURES:
- List 15-25 most important characters. Use full formal names.
- List 3-7 real-world historical figures mentioned.
- Provide a deep analysis for each (250-300 chars), covering their history/role up to %d%%.

2. LOCATIONS:
- List 5-10 significant locations (cities, buildings, landmarks).
- Concise descriptions (MAX 150 chars).

3. TIMELINE:
- Provide EXACTLY 1 key narrative highlight for EVERY narrative chapter up to the %d%% mark.
- Each event description MUST be MAX 120 characters.
- Ensure the timeline is strictly chronological.

STRICT RULES:
- NO SPOILERS: Stop all analysis and information exactly at the %d%% mark.
- FORMAT: Return ONLY valid JSON.

REQUIRED JSON FORMAT:
{
  "characters": [
    {
      "name": "Full Name",
      "role": "Role at %d%%",
      "gender": "Gender",
      "occupation": "Job",
      "description": "Deep analysis (250-300 chars). NO SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Full Name",
      "role": "Historical Role",
      "biography": "Bio (MAX 150 chars)",
      "importance_in_book": "Significance at %d%%",
      "context_in_book": "Context"
    }
  ],
  "locations": [
    {"name": "Place", "description": "Short desc (MAX 150 chars)", "importance": "Significance at %d%%"}
  ],
  "timeline": [
    {"event": "Event (MAX 120 chars)", "chapter": "Chapter Name", "importance": "High/Low"}
  ]
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
