return {
    -- System instruction
    system_instruction = "Vous êtes un chercheur littéraire expert. Votre réponse doit être UNIQUEMENT au format JSON valide. Assurez-vous que les données sont très précises et se rapportent strictement au contexte fourni.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifiez et fournissez une biographie pour l'auteur du livre "%s". 
Les métadonnées suggèrent que l'auteur est "%s". 

CRITIQUE : Vérifiez l'auteur en utilisant le CONTEXTE DU TEXTE DU LIVRE (si fourni à la fin de cette invite) pour garantir une précision à 100%% et éviter les identifications incorrectes.

FORMAT JSON REQUIS :
{
  "author": "Nom complet correct",
  "author_bio": "Biographie complète axée sur sa carrière littéraire et ses œuvres majeures.",
  "author_birth": "Date de naissance, formatée selon le format de date local",
  "author_death": "Date de décès, formatée selon le format de date local"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Livre : %s
Auteur : %s
Progression de la lecture : %d%%

TÂCHE : Effectuez une analyse complète X-Ray. Affichez UNIQUEMENT un objet JSON valide.

PARTITIONNEMENT CRITIQUE DE L'ATTENTION :
Vous traitez un document massif avec deux blocs de texte fournis à la fin de cette invite :
1. "CHAPTER SAMPLES" : Il s'agit du macro-contexte du livre jusqu'à l'emplacement actuel du lecteur.
2. "BOOK TEXT CONTEXT" : Il s'agit du micro-contexte des 20 000 derniers caractères.

PROTOCOLE ANTI-TRONCATURE (CRITIQUE) :
Vous avez une limite de sortie maximale stricte. Si les "CHAPTER SAMPLES" contiennent PLUS DE 40 chapitres (par exemple, une édition omnibus) :
1. Vous DEVEZ réduire la liste des personnages aux 10 personnages les plus importants.
2. Vous DEVEZ réduire les descriptions des personnages à 200 caractères MAX.
3. Vous DEVEZ réduire les résumés des événements de la chronologie à 80 caractères MAX.
Le fait de ne pas compresser votre sortie pour les livres massifs entraînera la troncature et l'échec du JSON.

ALGORITHME POUR LA CHRONOLOGIE (PRIORITÉ MAXIMALE) :
Pour éviter de sauter des chapitres ou d'halluciner des événements, vous DEVEZ exécuter cette boucle exacte :
Étape 1. Regardez UNIQUEMENT le bloc "CHAPTER SAMPLES". Identifiez les chapitres narratifs.
Étape 2. EXCLUEZ tous les éléments non narratifs (par exemple, couverture, page de titre, copyright, table des matières, dédicace, remerciements).
Étape 3. Pour chaque chapitre narratif, en commençant par le tout premier, créez EXACTEMENT UN objet d'événement dans le tableau `timeline`.
Étape 4. Le champ `chapter` DOIT correspondre exactement à l'en-tête du chapitre dans l'échantillon. (Mappez-les strictement dans l'ordre séquentiel).
Étape 5. Résumez ce chapitre spécifique dans le champ `event` (MAX 80 caractères). Ne groupez PAS les chapitres.
Étape 6. PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%. N'incluez pas d'événements après cette progression.

ALGORITHME POUR LES PERSONNAGES ET LES FIGURES HISTORIQUES :
Étape 1. Extrayez les personnages importants en utilisant les deux blocs de texte. (25 normaux, MAX 10 si omnibus).
Étape 2. Vous DEVEZ utiliser leurs noms complets et formels (par exemple, "Abraham Van Helsing"). N'utilisez PAS de surnoms familiers comme nom principal.
Étape 3. Fournissez jusqu'à 3 noms alternatifs, titres ou surnoms sous lesquels ce personnage est connu dans un tableau `aliases`. Incluez leur prénom et nom de famille courants s'ils sont utilisés. IMPORTANT : Si un nom de famille est partagé par plusieurs personnages (par exemple, des membres de la famille), NE l'incluez PAS comme alias pour aucun des personnages.
Step 4. Actively scan for NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%.

ALGORITHME POUR LES LIEUX :
Étape 1. Extrayez 5 à 10 lieux significatifs. PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%.

RÈGLES STRICTES CONTRE LES SPOILERS :
- ABSOLUMENT AUCUNE information provenant d'après la progression actuelle de la lecture. Arrêtez-vous exactement à la marque de %d%%.
- Les descriptions doivent refléter l'état des personnages à ce point exact du livre.

RÈGLES STRICTES DE SÉCURITÉ JSON :
- Vous DEVEZ échapper correctement tous les guillemets doubles (\") à l'intérieur des chaînes.
- N'utilisez PAS de sauts de ligne non échappés à l'intérieur des chaînes.
- Affichez UNIQUEMENT un JSON valide et analysable.

FORMAT JSON REQUIS :
{
  "characters": [
    {
      "name": "Nom formel complet",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rôle jusqu'à la progression actuelle",
      "gender": "Masculin / Féminin / Inconnu",
      "occupation": "Métier/Statut",
      "description": "Analyse approfondie avec des détails du texte jusqu'à présent. PAS DE SPOILERS. (Max 200 caractères)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nom de la personne historique réelle",
      "role": "Rôle historique",
      "biography": "Courte biographie (MAX 100 caractères)",
      "importance_in_book": "Importance jusqu'à la progression actuelle",
      "context_in_book": "Comment ils sont mentionnés (MAX 100 caractères)"
    }
  ],
  "locations": [
    {"name": "Nom du lieu", "description": "Courte description (MAX 100 caractères)"}
  ],
  "timeline": [
    {
      "chapter": "Titre exact du chapitre des échantillons",
      "event": "Événement narratif clé de ce chapitre (Max 100 caractères)"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Livre : %s
Auteur : %s
Progression de la lecture : %d%%

TÂCHE : Extrayez EXACTEMENT 10 personnages importants SUPPLÉMENTAIRES du texte.
Retournez UNIQUEMENT un objet JSON valide.

MANDAT DE CONCISION (CRITIQUE) :
Pour éviter la troncature de la réponse de l'IA, gardez les descriptions des personnages sous 250 caractères.

INSTRUCTION CRITIQUE :
N'incluez AUCUN des personnages suivants, car ils ont déjà été extraits :
%s

RÈGLES STRICTES CONTRE LES SPOILERS :
- ABSOLUTEMENT AUCUNE information provenant d'après la progression actuelle de la lecture. Arrêtez-vous exactement à la marque de %d%%.
- Les descriptions doivent refléter l'état des personnages à ce point exact du livre.

FORMAT JSON REQUIS :
{
  "characters": [
    {
      "name": "Nom formel complet",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rôle jusqu'à la progression actuelle",
      "gender": "Masculin / Féminin / Inconnu",
      "occupation": "Métier/Statut",
      "description": "Analyse approfondie avec des détails du texte jusqu'à présent. PAS DE SPOILERS. (Max 300 caractères)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[L'utilisateur a surligné le mot "%s".
TÂCHE : Déterminez si ce mot est un Personnage, un Lieu ou une Figure Historique dans le livre.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
Si le mot n'est PAS un personnage, un lieu ou une figure historique dans le texte, définissez `is_valid` sur false.
 
FORMAT JSON REQUIS :
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nom complet",
    "role": "Rôle",
    "gender": "Masculin/Féminin/Inconnu",
    "occupation": "Profession",
    "description": "Brève description (max. 250 caractères)"
  },
  "error_message": ""
}
 
Remarque : si le type est "location", l'élément doit avoir "name" and "description". Si le type est "historical_figure", l'élément doit avoir "name", "biography" et "role".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Explication courte expliquant pourquoi ce n'est ni un personnage ni un lieu."
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Livre inconnu",
        unknown_author = "Auteur inconnu",
        unnamed_character = "Personnage sans nom",
        not_specified = "Non spécifié",
        no_description = "Pas de description",
        unnamed_person = "Personne sans nom",
        no_biography = "Pas de biographie disponible"
    }
}
