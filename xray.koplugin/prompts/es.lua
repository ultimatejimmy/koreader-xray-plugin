return {
    -- Instrucción del sistema
    system_instruction = "Eres un experto investigador literario. Tu respuesta debe estar ÚNICAMENTE en formato JSON válido. Asegúrate de que los datos sean altamente precisos y pertenezcan estrictamente al contexto proporcionado.",

    -- Mensaje solo para el autor (Para búsqueda rápida de biografía)
    author_only = [[Identifica y proporciona una biografía del autor del libro "%s". 
Los metadatos sugieren que el autor es "%s". 

CRÍTICO: Verifica el autor utilizando el CONTEXTO DEL TEXTO DEL LIBRO (si se proporciona al final de este mensaje) para garantizar el 100% de precisión y evitar identificaciones incorrectas.

FORMATO JSON REQUERIDO:
{
  "author": "Nombre Completo Correcto",
  "author_bio": "Biografía exhaustiva centrada en su carrera literaria y obras principales.",
  "author_birth": "Fecha de nacimiento, formateada según el formato de fecha local",
  "author_death": "Fecha de fallecimiento, formateada según el formato de fecha local"
}]],

    -- Obtención integral única (Personajes, ubicaciones y línea de tiempo combinados)
    comprehensive_xray = [[Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Realiza un análisis X-Ray completo. Devuelve ÚNICAMENTE un objeto JSON válido.

PARTICIÓN CRÍTICA DE ATENCIÓN:
Estás procesando un documento masivo con dos bloques de texto proporcionados al final de esta instrucción:
1. "CHAPTER SAMPLES" (Muestras de capítulos): Este es el macrocontexto del libro hasta la ubicación actual del lector.
2. "BOOK TEXT CONTEXT" (Contexto del texto del libro): Este es el microcontexto de los últimos 20,000 caracteres.

PROTOCOLO ANTI-TRUNCAMIENTO (CRÍTICO):
Tienes un límite máximo de salida estricto. Si las "CHAPTER SAMPLES" contienen MÁS DE 40 capítulos (ej. una edición ómnibus):
1. DEBES reducir la lista de personajes a ÚNICAMENTE los 10 personajes más importantes.
2. DEBES reducir las descripciones de los personajes a un MÁXIMO de 200 caracteres.
3. DEBES reducir los resúmenes de eventos de la línea de tiempo a un MÁXIMO de 80 caracteres.
Si no comprimes tu salida para libros masivos, el JSON se truncará y fallará.

ALGORITMO PARA LA LÍNEA DE TIEMPO (MÁXIMA PRIORIDAD):
Para evitar saltar capítulos o alucinar eventos, DEBES ejecutar este bucle exacto:
Paso 1. Mira ÚNICAMENTE el bloque "CHAPTER SAMPLES". Identifica los capítulos narrativos.
Paso 2. EXCLUYE todo el material inicial y final no narrativo (ej., Portada, Página de título, Derechos de autor, Índice, Dedicatoria, Agradecimientos, También de).
Paso 3. Para cada capítulo narrativo, comenzando desde el primero, crea EXACTAMENTE UN objeto de evento en la matriz `timeline`.
Paso 4. El campo `chapter` DEBE coincidir exactamente con el encabezado del capítulo en la muestra. (Mapéalos estrictamente en orden secuencial).
Paso 5. Resume ese capítulo específico en el campo `event` (MÁX 80 caracteres). NO agrupes capítulos.
Paso 6. SIN SPOILERS: Detente exactamente en la marca del %d%%. No incluyas eventos más allá de este progreso.

ALGORITMO PARA PERSONAJES Y FIGURAS HISTÓRICAS:
Paso 1. Extrae personajes importantes usando ambos bloques de texto. (25 normal, MÁXIMO 10 si es ómnibus).
Paso 2. DEBES usar sus nombres completos y formales (ej. "Abraham Van Helsing"). NO uses apodos informales como nombre principal.
Paso 3. Proporciona hasta 3 nombres alternativos, títulos o apodos por los que se conozca a este personaje en una matriz `aliases`. Incluye su nombre y apellido comunes si se usan. IMPORTANTE: Si un apellido es compartido por varios personajes (ej., miembros de la familia), NO lo incluyas como alias para ninguno de ellos.
Paso 4. Escanea activamente personas REALES de la historia humana (ej. Presidentes, Autores, Generales). Añádelos a `historical_figures`.
SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA UBICACIONES:
Paso 1. Extrae de 5 a 10 ubicaciones significativas. SIN SPOILERS: Detente exactamente en la marca del %d%%.

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.
- Las descripciones deben reflejar el estado de los personajes en este punto exacto del libro.

REGLAS ESTRICTAS DE SEGURIDAD JSON:
- DEBES escapar correctamente todas las comillas dobles (\") dentro de las cadenas.
- NO uses saltos de línea sin escapar dentro de las cadenas.
- Genera ÚNICAMENTE JSON válido y analizable.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nombre Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel hasta el progreso actual",
      "gender": "Masculino / Femenino / Desconocido",
      "occupation": "Trabajo/Estado",
      "description": "Análisis profundo con detalles del texto hasta ahora. SIN SPOILERS. (Máx 200 caracteres)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nombre de la Persona Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografía breve (MÁX 100 caracteres)",
      "importance_in_book": "Significancia hasta el progreso actual",
      "context_in_book": "Cómo se mencionan (MÁX 100 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nombre del Lugar", "description": "Descripción breve (MÁX 100 caracteres)"}
  ],
  "timeline": [
    {
      "chapter": "Título exacto del capítulo de las muestras",
      "event": "Evento narrativo clave de este capítulo (Máx 100 caracteres)"
    }
  ]
} ]],

    -- Obtención de más personajes (Bypass del límite de IA)
    more_characters = [[Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Extrae EXACTAMENTE 10 personajes importantes ADICIONALES del texto.
Devuelve ÚNICAMENTE un objeto JSON válido.

MANDATO DE BREVEDAD (CRÍTICO):
Para evitar el truncamiento de la respuesta de la IA, mantén las descripciones de los personajes por debajo de los 250 caracteres.

INSTRUCCIÓN CRÍTICA:
NO incluyas ninguno de los siguientes personajes, ya que ya han sido extraídos:
%s

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.
- Las descripciones deben reflejar el estado de los personajes en este punto exacto del libro.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nombre Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel hasta el progreso actual",
      "gender": "Masculino / Femenino / Desconocido",
      "occupation": "Trabajo/Estado",
      "description": "Análisis profundo con detalles del texto hasta ahora. SIN SPOILERS. (Máx 300 caracteres)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[El usuario ha resaltado la palabra "%s".
TAREA: Determine si esta palabra es un Personaje, Lugar o Figura Histórica en el libro.
 
IMPORTANTE: Utilice ÚNICAMENTE el "BOOK TEXT CONTEXT" proporcionado para tomar su decisión. No utilice conocimientos externos ni alucine.
Si la palabra NO es un personaje, lugar o figura histórica en el texto, establezca `is_valid` en false.
 
FORMATO JSON REQUERIDO:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nombre completo",
    "role": "Papel",
    "gender": "Masculino/Femenino/Desconocido",
    "occupation": "Ocupación",
    "description": "Breve descripción (máx. 250 caracteres)"
  },
  "error_message": ""
}
 
Nota: si el tipo es "location", el elemento debe tener "name" and "description". Si el tipo es "historical_figure", el elemento debe tener "name", "biography" y "role".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Breve explicación de por qué esto no es un personaje ni un lugar."
}]],

    -- Cadenas de respaldo
    fallback = {
        unknown_book = "Libro desconocido",
        unknown_author = "Autor desconocido",
        unnamed_character = "Personaje sin nombre",
        not_specified = "No especificado",
        no_description = "Sin descripción",
        unnamed_person = "Persona sin nombre",
        no_biography = "Biografía no disponible"
    }
}
