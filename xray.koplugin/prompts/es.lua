return {
    -- Instrucción del sistema
    system_instruction = "Eres un experto investigador literario. Tu respuesta debe estar ÚNICAMENTE en formato JSON válido. Asegúrate de que los datos sean altamente precisos y pertenezcan estrictamente al contexto proporcionado.",

    -- Mensaje solo para el autor (Para búsqueda rápida de biografía)
    author_only = [[Identifica y proporciona una biografía del autor del libro "%s". 
Los metadatos sugieren que el autor es "%s", pero verifícalo basándote en el título del libro.

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
Paso 3. Escanea activamente personas REALES de la historia humana (ej. Presidentes, Autores, Generales). Añádelos a `historical_figures`.
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
      "role": "Papel hasta el progreso actual",
      "gender": "Masculino / Femenino / Desconocido",
      "occupation": "Trabajo/Estado",
      "description": "Análisis profundo con detalles del texto hasta ahora. SIN SPOILERS. (Máx 300 caracteres)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nombre de la Persona Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografía breve (MÁX 150 caracteres)",
      "importance_in_book": "Significancia hasta el progreso actual",
      "context_in_book": "Cómo se mencionan (MÁX 150 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nombre del Lugar", "description": "Descripción breve (MÁX 150 caracteres)"}
  ],
  "timeline": [
    {
      "chapter": "Título exacto del capítulo de las muestras",
      "event": "Evento narrativo clave de este capítulo (Máx 150 caracteres)"
    }
  ]
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
