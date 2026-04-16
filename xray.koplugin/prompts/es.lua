return {
    -- Specialized section for Characters and Historical Figures
    character_section = [[Libro: "%s" - Autor: %s
Progreso de lectura: %d%%

TAREA: Enumere los 15-25 personajes más importantes y 3-7 figuras históricas del mundo real mencionadas hasta la marca del %d%%.

REGLAS:
1. PROFUNDIDAD DEL PERSONAJE: Proporcione un análisis exhaustivo (250-300 caracteres) para cada personaje, que abarque toda su historia y papel hasta la marca del %d%%.
2. CONTROL DE SPOILERS: ABSOLUTAMENTE NINGUNA información después de la marca del %d%%.
3. CALIDAD: Centrarse en la importancia narrativa.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nombre completo",
      "role": "Papel al %d%%",
      "gender": "Género",
      "occupation": "Trabajo",
      "description": "Historia/análisis exhaustivo (250-300 caracteres). SIN SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Nombre",
      "role": "Papel",
      "biography": "Biografía corta (MÁX 150 caracteres)",
      "importance_in_book": "Significancia al %d%%",
      "context_in_book": "Contexto"
    }
  ]
}]],

    -- Specialized section for Locations
    location_section = [[Libro: "%s" - Autor: %s
Progreso de lectura: %d%%

TAREA: Enumere 5-10 ubicaciones significativas visitadas o mencionadas hasta la marca del %d%%.

REGLAS:
1. SIN SPOILERS: No mencione ubicaciones o eventos que ocurran después de la marca del %d%%.
2. CONCISIÓN: Las descripciones deben tener un MÁXIMO de 150 caracteres.

FORMATO JSON REQUERIDO:
{
  "locations": [
    {"name": "Lugar", "description": "Descripción corta (MÁX 150 caracteres)", "importance": "Significancia al %d%%"}
  ]
}]],

    -- Specialized section for Timeline
    timeline_section = [[Libro: "%s" - Autor: %s
Progreso de lectura: %d%%

TAREA: Cree una cronología de los eventos narrativos clave hasta la marca del %d%%.

REGLAS:
1. COBERTURA: Proporcione 1 punto destacado para CADA capítulo narrativo hasta la marca del %d%%.
2. EXCLUSIÓN: IGNORE el índice, las dedicatorias o el material preliminar.
3. BREVEDAD: Cada descripción de evento debe tener un MÁXIMO de 120 caracteres.
4. SIN SPOILERS: Deténgase exactamente en la marca del %d%%.

FORMATO JSON REQUERIDO:
{
  "timeline": [
    {"event": "Evento narrativo clave (MÁX 120 caracteres)", "chapter": "Nombre/Número del capítulo", "importance": "Alta/Baja"}
  ]
}]],
}
