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

ALGORITMO PARA LA LÍNEA DE TIEMPO (MÁXIMA PRIORIDAD):
Sufres de sesgo de recencia. Para evitar saltar capítulos o combinarlos, DEBES ejecutar este bucle exacto:
Paso 1. Mira ÚNICAMENTE el bloque "CHAPTER SAMPLES". Cuenta los capítulos narrativos.
Paso 2. Comienza en el primer capítulo de las muestras. Crea EXACTAMENTE UN objeto de evento en la matriz `timeline`.
Paso 3. El campo `chapter` DEBE coincidir exactamente con el encabezado del capítulo en la muestra. (NOTA: Si esto es un ómnibus que contiene varios libros, los títulos de los capítulos pueden repetirse o reiniciarse. Mapéalos estrictamente en el orden secuencial proporcionado).
Paso 4. Resume ese capítulo específico en el campo `event` (Máximo 200 caracteres).
Paso 5. Pasa al SIGUIENTE capítulo en las muestras y repite el Paso 2.
Paso 6. NO te detengas hasta que CADA capítulo de las muestras tenga EXACTAMENTE UN evento correspondiente. No los agrupes. SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA PERSONAJES Y FIGURAS HISTÓRICAS:
Paso 1. Extrae de 15 a 25 personajes importantes usando ambos bloques de texto.
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
      "description": "Análisis profundo (250-300 caracteres). SIN SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Nombre de la Persona Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografía breve (MÁX 150 caracteres)",
      "importance_in_book": "Significancia hasta el progreso actual",
      "context_in_book": "Cómo se mencionan"
    }
  ],
  "locations": [
    {"name": "Nombre del Lugar", "description": "Descripción breve (MÁX 150 caracteres)"}
  ],
  "timeline": [
    {
      "chapter": "Título exacto del capítulo de las muestras",
      "event": "Evento narrativo clave de este capítulo (MÁX 150 caracteres)"
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
