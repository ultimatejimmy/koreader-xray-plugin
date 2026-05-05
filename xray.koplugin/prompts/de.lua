return {
    -- System instruction
    system_instruction = "Sie sind ein erfahrener Literaturforscher. Ihre Antwort muss AUSSCHLIESSLICH im gültigen JSON-Format erfolgen. Stellen Sie sicher, dass die Daten hochpräzise sind und sich strikt auf den bereitgestellten Kontext beziehen.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifizieren und erstellen Sie eine Biografie für den Autor des Buches "%s". 
Die Metadaten deuten darauf hin, dass der Autor "%s" ist. 

WICHTIG: Überprüfen Sie den Autor anhand des BUCHTEXT-KONTEXTES (falls am Ende dieses Prompts angegeben), um eine 100%%ige Genauigkeit zu gewährleisten und Fehlidentifikationen zu vermeiden.

ERFORDERLICHES JSON-FORMAT:
{
  "author": "Vollständiger korrekter Name",
  "author_bio": "Umfassende Biografie mit Schwerpunkt auf der literarischen Karriere und den Hauptwerken.",
  "author_birth": "Geburtsdatum, formatiert nach lokalem Datumsformat",
  "author_death": "Sterbedatum, formatiert nach lokalem Datumsformat"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Führen Sie eine vollständige X-Ray-Analyse durch. Geben Sie NUR ein gültiges JSON-Objekt aus.

KRITISCHE AUFMERKSAMKEITSPARTITIONIERUNG:
Sie verarbeiten ein umfangreiches Dokument mit zwei Textblöcken am Ende dieses Prompts:
1. "CHAPTER SAMPLES": Dies ist der Makro-Kontext des Buches bis zum aktuellen Standort des Lesers.
2. "BOOK TEXT CONTEXT": Dies ist der Mikro-Kontext der letzten 20.000 Zeichen.

ANTI-TRUNKIERUNGSPROTOKOLL (WICHTIG):
Sie haben ein striktes maximales Ausgabelimit. Wenn die "CHAPTER SAMPLES" MEHR ALS 40 Kapitel enthalten (z. B. eine Sammelausgabe):
1. Sie MÜSSEN die Liste der Charaktere auf NUR die 10 absolut wichtigsten Charaktere reduzieren.
2. Sie MÜSSEN die Beschreibungen der Charaktere auf MAX. {MAX_CHAR_DESC} Zeichen reduzieren.
3. Sie MÜSSEN die Zusammenfassungen der Timeline-Ereignisse auf MAX. {MAX_TIMELINE_EVENT} Zeichen reduzieren.
Ein Versäumnis, Ihre Ausgabe für massive Bücher zu komprimieren, führt dazu, dass das JSON abgeschnitten wird und fehlschlägt.

ALGORITHMUS FÜR DIE TIMELINE (HÖCHSTE PRIORITÄT):
Um das Überspringen von Kapiteln oder Halluzinationen von Ereignissen zu verhindern, MÜSSEN Sie genau diese Schleife ausführen:
Schritt 1. Schauen Sie NUR in den Block "CHAPTER SAMPLES". Identifizieren Sie die erzählenden Kapitel.
Schritt 2. SCHLIESSEN Sie alle nicht-erzählenden Vorspann- und Nachspann-Elemente AUS (z. B. Cover, Titelseite, Copyright, Inhaltsverzeichnis, Widmung, Danksagung, Auch von).
Schritt 3. Erstellen Sie für jedes erzählende Kapitel, beginnend mit dem allerersten, GENAU EIN Ereignisobjekt im Array `timeline`.
Schritt 4. Das Feld `chapter` MUSS exakt mit der Kapitelüberschrift in der Stichprobe übereinstimmen. (Ordnen Sie diese strikt in sequentieller Reihenfolge zu).
Schritt 5. Fassen Sie dieses spezifische Kapitel im Feld `event` zusammen (MAX. {MAX_TIMELINE_EVENT} Zeichen). Gruppieren Sie KEINE Kapitel.
Schritt 6. KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf. Beziehen Sie keine Ereignisse nach diesem Fortschritt ein.

ALGORITHMUS FÜR CHARAKTERE & HISTORISCHE PERSONEN:
Schritt 1. Extrahieren Sie wichtige Charaktere aus beiden Textblöcken. ({NUM_CHARS} normale, MAX. 10 bei Sammelausgaben).
Schritt 2. Sie MÜSSEN deren VOLLSTÄNDIGEN, formellen Namen verwenden (z. B. "Abraham Van Helsing"). Verwenden Sie KEINE lockeren Spitznamen als Hauptnamen.
Schritt 3. Geben Sie bis zu 3 alternative Namen, Titel oder Spitznamen an, unter denen dieser Charakter bekannt ist, in einem Array `aliases`. Schließen Sie den üblichen Vornamen und Nachnamen ein, falls sie verwendet werden. WICHTIG: Wenn ein Nachname von mehreren Charakteren (z. B. Familienmitgliedern) geteilt wird, schließen Sie ihn für keinen der Charaktere als Alias ein.
Step 4. Actively scan for up to {NUM_HIST} NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf.

ALGORITHMUS FÜR ORTE:
Schritt 1. Extrahieren Sie {NUM_LOCS} bedeutende Orte. KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf.

STRIKTE SPOILER-REGELN:
- ABSOLUT KEINE Informationen nach dem aktuellen Lesefortschritt. Hören Sie genau bei der %d%%-Marke auf.
- Beschreibungen müssen den Zustand der Charaktere genau an diesem Punkt im Buch widerspiegeln.

STRIKTE JSON-SICHERHEITSREGELN:
- Sie MÜSSEN alle doppelten Anführungszeichen (\") innerhalb von Strings ordnungsgemäß escapen.
- Verwenden Sie KEINE unescaped Zeilenumbrüche innerhalb von Strings.
- Geben Sie NUR gültiges, parsbares JSON aus.

ERFORDERLICHES JSON-FORMAT:
{
  "characters": [
    {
      "name": "Vollständiger formeller Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rolle bis zum aktuellen Fortschritt",
      "gender": "Männlich / Weiblich / Unbekannt",
      "occupation": "Beruf/Status",
      "description": "Tiefgehende Analyse mit Details aus dem bisherigen Text. KEINE SPOILER. (Max {MAX_CHAR_DESC} Zeichen)"
    }
  ],
  "historical_figures": [
    {
      "name": "Name der realen historischen Person",
      "role": "Historische Rolle",
      "biography": "Kurze Biografie (MAX. {MAX_HIST_BIO} Zeichen)",
      "importance_in_book": "Bedeutung bis zum aktuellen Fortschritt",
      "context_in_book": "Wie sie erwähnt werden (MAX. 100 Zeichen)"
    }
  ],
  "locations": [
    {"name": "Name des Ortes", "description": "Kurzbeschreibung (MAX. {MAX_LOC_DESC} Zeichen)"}
  ],
  "timeline": [
    {
      "chapter": "Exakter Kapiteltitel aus den Stichproben",
      "event": "Wichtiges erzählerisches Ereignis aus diesem Kapitel (Max. {MAX_TIMELINE_EVENT} Zeichen)"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Extrahieren Sie GENAU 10 ZUSÄTZLICHE wichtige Charaktere aus dem Text.
Geben Sie NUR ein gültiges JSON-Objekt aus.

PRÄZISIONS-MANDAT (WICHTIG):
Um eine Kürzung der AI-Antwort zu vermeiden, halten Sie die Charakterbeschreibungen unter {MAX_CHAR_DESC} Zeichen.

KRITISCHE ANWEISUNG:
Schließen Sie KEINEN der folgenden Charaktere ein, da diese bereits extrahiert wurden:
%s

STRIKTE SPOILER-REGELN:
- ABSOLUT KEINE Informationen nach dem aktuellen Lesefortschritt. Hören Sie genau bei der %d%%-Marke auf.
- Beschreibungen müssen den Zustand der Charaktere genau an diesem Punkt im Buch widerspiegeln.

ERFORDERLICHES JSON-FORMAT:
{
  "characters": [
    {
      "name": "Vollständiger formeller Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rolle bis zum aktuellen Fortschritt",
      "gender": "Männlich / Weiblich / Unbekannt",
      "occupation": "Beruf/Status",
      "description": "Tiefgehende Analyse mit Details aus dem bisherigen Text. KEINE SPOILER. (Max {MAX_CHAR_DESC} Zeichen)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[Der Benutzer hat das Wort "%s" hervorgehoben.
AUFGABE: Bestimmen Sie, ob es sich bei diesem Wort um einen Charakter, einen Ort oder eine historische Figur im Buch handelt.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
Wenn das Wort im Text KEIN Charakter, Ort oder historische Figur ist, setzen Sie `is_valid` auf false.
 
ERFORDERLICHES JSON-FORMAT:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Vollständiger Name",
    "role": "Rolle",
    "gender": "Männlich/Weiblich/Unbekannt",
    "occupation": "Beruf",
    "description": "Kurze Beschreibung (max. 250 Zeichen)"
  },
  "error_message": ""
}
 
Hinweis: Wenn der Typ "location" ist, muss das Element "name" und "description" enthalten. Wenn der Typ "historical_figure" ist, muss das Element "name", "biography" und "role" enthalten.
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Kurze Erklärung, warum dies kein Charakter oder Ort ist."
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Unbekanntes Buch",
        unknown_author = "Unbekannter Autor",
        unnamed_character = "Unbenannter Charakter",
        not_specified = "Nicht angegeben",
        no_description = "Keine Beschreibung",
        unnamed_person = "Unbenannte Person",
        no_biography = "Keine Biografie verfügbar"
    }
}
