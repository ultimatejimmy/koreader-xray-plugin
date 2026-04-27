return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identify and provide biography for the author of the book "%s". 
Metadata suggests the author is "%s". 

CRITICAL: Verify the author using the BOOK TEXT CONTEXT (if provided at the end of this prompt) to ensure 100% accuracy and avoid incorrect identifications.

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

ANTI-TRUNCATION PROTOCOL (CRITICAL):
You have a strict maximum output limit. If the "CHAPTER SAMPLES" contains MORE THAN 40 chapters (e.g., an omnibus edition):
1. You MUST reduce the characters list to ONLY the top 10 absolute most important characters.
2. You MUST reduce character descriptions to MAX 200 characters.
3. You MUST reduce timeline event summaries to MAX 80 characters.
Failure to compress your output for massive books will cause the JSON to truncate and fail.

ALGORITHM FOR TIMELINE (HIGHEST PRIORITY):
To prevent skipping chapters or hallucinating events, you MUST execute this exact loop:
Step 1. Look ONLY at the "CHAPTER SAMPLES" block. Identify the narrative chapters.
Step 2. EXCLUDE all non-narrative frontmatter and backmatter (e.g., Cover, Title Page, Copyright, Table of Contents, Dedication, Acknowledgments, Also By).
Step 3. For each narrative chapter, starting from the very first one, create EXACTLY ONE event object in the `timeline` array.
Step 4. The `chapter` field MUST exactly match the chapter header in the sample. (Map them strictly in sequential order).
Step 5. Summarize that specific chapter in the `event` field (MAX 80 chars). Do NOT group chapters.
Step 6. NO SPOILERS: Stop exactly at the %d%% mark. Do not include events past this progress.

ALGORITHM FOR CHARACTERS & HISTORICAL FIGURES:
Step 1. Extract important characters using both text blocks. (25 normal, MAX 10 if omnibus).
Step 2. You MUST use their FULL, formal names (e.g., "Abraham Van Helsing"). Do NOT use casual nicknames as the main name.
Step 3. Provide up to 3 alternative names, titles, or nicknames this character goes by in an `aliases` array. Include their common first name and last name if used. IMPORTANT: If a last name is shared by multiple characters (e.g., family members), DO NOT include it as an alias for either character.
Step 4. Actively scan for REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
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
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Role up to current progress",
      "gender": "Male / Female / Unknown",
      "occupation": "Job/Status",
      "description": "Deep analysis with details from the text so far. NO SPOILERS. (Max 200 chars)"
    }
  ],
  "historical_figures": [
    {
      "name": "Real Historical Person Name",
      "role": "Historical Role",
      "biography": "Short biography (MAX 100 chars)",
      "importance_in_book": "Significance up to current progress",
      "context_in_book": "How they are mentioned (MAX 100 chars)"
    }
  ],
  "locations": [
    {"name": "Place Name", "description": "Short desc (MAX 100 chars)"}
  ],
  "timeline": [
    {
      "chapter": "Exact Chapter Title from Samples",
      "event": "Key narrative event from this chapter (Max 100 chars)"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Book: %s
Author: %s
Reading Progress: %d%%

TASK: Extract EXACTLY 10 ADDITIONAL important characters from the text.
Return ONLY a valid JSON object.

CONCISENESS MANDATE (CRITICAL):
To avoid AI response truncation, keep character descriptions under 250 characters.

CRITICAL INSTRUCTION:
Do NOT include any of the following characters, as they have already been extracted:
%s

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

REQUIRED JSON FORMAT:
{
  "characters": [
    {
      "name": "Full Formal Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Role up to current progress",
      "gender": "Male / Female / Unknown",
      "occupation": "Job/Status",
      "description": "Deep analysis with details from the text so far. NO SPOILERS. (Max 300 chars)"
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