return {
    -- Specialized section for Characters and Historical Figures
    character_section = [[Livro: "%s" - Autor: %s
Progresso de leitura: %d%%

TAREFA: Liste os 15-25 personagens mais importantes e 3-7 figuras históricas do mundo real mencionadas até a marca de %d%%.

REGRAS:
1. PROFUNDIDADE DO PERSONAGEM: Forneça uma análise abrangente (250-300 caracteres) para cada personagem, englobando toda a sua história e papel até a marca de %d%%.
2. CONTROLE DE SPOILER: ABSOLUTAMENTE NENHUMA informação após a marca de %d%%.
3. QUALIDADE: Foque na significância narrativa.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nome Completo",
      "role": "Papel em %d%%",
      "gender": "Gênero",
      "occupation": "Trabalho",
      "description": "História/análise abrangente (250-300 chars). SEM SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Nome",
      "role": "Papel",
      "biography": "Bio curta (MÁX 150 chars)",
      "importance_in_book": "Significância em %d%%",
      "context_in_book": "Contexto"
    }
  ]
}]],

    -- Specialized section for Locations
    location_section = [[Livro: "%s" - Autor: %s
Progresso de leitura: %d%%

TAREFA: Liste 5-10 locais significativos visitados ou mencionados até a marca de %d%%.

REGRAS:
1. SEM SPOILERS: Não mencione locais ou eventos que ocorram após a marca de %d%%.
2. CONCISÃO: As descrições devem ter no MÁXIMO 150 caracteres.

FORMATO JSON REQUERIDO:
{
  "locations": [
    {"name": "Lugar", "description": "Desc curta (MÁX 150 chars)", "importance": "Significância em %d%%"}
  ]
}]],

    -- Specialized section for Timeline
    timeline_section = [[Livro: "%s" - Autor: %s
Progresso de leitura: %d%%

TAREFA: Crie uma linha do tempo cronológica dos principais eventos narrativos até a marca de %d%%.

REGRAS:
1. COBERTURA: Forneça 1 destaque para CADA capítulo narrativo até a marca de %d%%.
2. EXCLUSÃO: IGNORE Índice, Dedicatórias ou Prefácios.
3. BREVIDADE: Cada descrição de evento deve ter no MÁXIMO 120 caracteres.
4. SEM SPOILERS: Pare exatamente na marca de %d%%.

FORMATO JSON REQUERIDO:
{
  "timeline": [
    {"event": "Evento principal (MÁX 120 chars)", "chapter": "Nome/Número do Capítulo", "importance": "Alta/Baixa"}
  ]
}]],
}
