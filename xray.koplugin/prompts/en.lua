return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identify and provide biography for the author of the book "%s". 
Metadata suggests the author is "%s", but verify this based on the book title.

REQUIRED JSON FORMAT:
{
  "author": "Correct Full Name",
  "author_bio": "Comprehensive biography focusing on their literary career and major works.",
  "author_birth": "Birth Date, formatted based on local date format",
  "author_death": "Death Date, formatted based on local date format"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Book: %s
Author: %s
Reading Progress: %d%%

TASK: Perform a complete X-Ray analysis. Output ONLY a valid JSON object.

CRITICAL ATTENTION PARTITIONING:
You are processing a massive document with two text blocks provided at the end of this prompt:
1. "CHAPTER SAMPLES": This is the macro-context of the book up to the reader's current location.
2. "BOOK TEXT CONTEXT": This is the micro-context of the most recent 20k characters.

ALGORITHM FOR TIMELINE (HIGHEST PRIORITY):
You suffer from recency bias. To prevent skipping chapters or combining them, you MUST execute this exact loop:
Step 1. Look ONLY at the "CHAPTER SAMPLES" block. Count the narrative chapters.
Step 2. Start at the very first chapter in the samples. Create EXACTLY ONE event object in the `timeline` array.
Step 3. The `chapter` field MUST exactly match the chapter header in the sample. (NOTE: If this is an omnibus containing multiple books, chapter titles might repeat or reset. Map them strictly in the sequential order provided).
Step 4. Summarize that specific chapter in the `event` field (Max 200 chars).
Step 5. Move to the NEXT chapter in the samples and repeat Step 2.
Step 6. Do NOT stop until EVERY single chapter in the samples has EXACTLY ONE corresponding event. Do not group them. NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR CHARACTERS & HISTORICAL FIGURES:
Step 1. Extract 15-25 important characters using both text blocks.
Step 2. You MUST use their FULL, formal names (e.g., "Abraham Van Helsing"). Do NOT use casual nicknames as the main name.
Step 3. Actively scan for REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR LOCATIONS:
Step 1. Extract 5-10 significant locations. NO SPOILERS: Stop exactly at the %d%% mark.

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

STRICT JSON SAFETY RULES:
- You MUST properly escape all double quotes (\") inside strings.
- Do NOT use unescaped line breaks inside strings.
- Output ONLY valid, parseable JSON.

REQUIRED JSON FORMAT:
{
  "characters": [
    {
      "name": "Full Formal Name",
      "role": "Role up to current progress",
      "gender": "Male / Female / Unknown",
      "occupation": "Job/Status",
      "description": "Deep analysis (250-300 chars). NO SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Real Historical Person Name",
      "role": "Historical Role",
      "biography": "Short biography (MAX 150 chars)",
      "importance_in_book": "Significance up to current progress",
      "context_in_book": "How they are mentioned"
    }
  ],
  "locations": [
    {"name": "Place Name", "description": "Short desc (MAX 150 chars)"}
  ],
  "timeline": [
    {
      "chapter": "Exact Chapter Title from Samples",
      "event": "Key narrative event from this chapter (MAX 150 chars)"
    }
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