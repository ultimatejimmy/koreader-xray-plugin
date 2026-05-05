return {
    -- Instrução do sistema
    system_instruction = "Você é um pesquisador literário especialista. Sua resposta deve estar APENAS no formato JSON válido. Certifique-se de que os dados sejam altamente precisos e pertençam estritamente ao contexto fornecido.",

    -- Mensagem apenas para o autor (Para busca rápida de biografia)
    author_only = [[Identifique e forneça a biografia do autor do livro "%s". 
Os metadatos sugerem que o autor é "%s". 

CRÍTICO: Verifique o autor usando o CONTEXTO DO TEXTO DO LIVRO (se fornecido no final desta mensagem) para garantir 100% de precisão e evitar identificações incorretas.

FORMATO JSON REQUERIDO:
{
  "author": "Nome Completo Correto",
  "author_bio": "Biografia abrangente focada em sua carreira literária e principais obras.",
  "author_birth": "Data de nascimento, formatada de acordo com o formato de data local",
  "author_death": "Data de falecimento, formatada de acordo com o formato de data local"
}]],

    -- Busca Abrangente Única (Personagens, Locais e Cronologia combinados)
    comprehensive_xray = [[Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Realize uma análise X-Ray completa. Retorne APENAS um objeto JSON válido.

PARTICIONAMENTO CRÍTICO DE ATENÇÃO:
Você está processando um documento massivo com dois blocos de texto fornecidos ao final desta instrução:
1. "CHAPTER SAMPLES" (Amostras de capítulos): Este é o macrocontexto do livro até a localização atual do leitor.
2. "BOOK TEXT CONTEXT" (Contexto do texto do livro): Este é o microcontexto dos últimos 20.000 caracteres.

PROTOCOLO ANTI-TRUNCAMENTO (CRÍTICO): Você tem um limite máximo de saída estrito. Se as "CHAPTER SAMPLES" contiverem MAIS DE 40 capítulos (ex: uma edição omnibus):
1. Você DEVE reduzir a lista de personagens para APENAS os 10 personagens mais importantes.
2. Você DEVE reduzir as descrições dos personagens para no MÁXIMO {MAX_CHAR_DESC} caracteres.
3. Você DEVE reduzir os resumos dos eventos da cronologia para no MÁXIMO {MAX_TIMELINE_EVENT} caracteres.
A falha em comprimir sua saída para livros massivos fará com que o JSON seja truncado e falhe.

ALGORITMO PARA CRONOLOGIA (PRIORIDADE MÁXIMA):
Para evitar pular capítulos ou alucinar eventos, você DEVE executar este loop exato:
Passo 1. Olhe APENAS para o bloco "CHAPTER SAMPLES". Identifique os capítulos narrativos.
Passo 2. EXCLUA todo o material pré-textual e pós-textual não narrativo (ex: Capa, Folha de Rosto, Direitos Autorais, Índice, Dedicatória, Agradecimentos, Também por).
Passo 3. Para cada capítulo narrativo, começando do primeiríssimo, crie EXATAMENTE UM objeto de evento no array `timeline`.
Passo 4. O campo `chapter` DEVE corresponder exatamente ao cabeçalho do capítulo na amostra. (Mapeie-os estritamente em ordem sequencial).
Passo 5. Resuma esse capítulo específico no campo `event` (MÁX {MAX_TIMELINE_EVENT} caracteres). NÃO agrupe capítulos.
Passo 6. SEM SPOILERS: Pare exatamente na marca de %d%%. Não inclua eventos após este progresso.

ALGORITMO PARA PERSONAGENS E FIGURAS HISTÓRICAS:
Passo 1. Extraia personagens importantes usando ambos os blocos de texto. ({NUM_CHARS} normal, no MÁXIMO 10 se for omnibus).
Passo 2. Você DEVE usar seus nomes completos e formais (ex: "Abraham Van Helsing"). NÃO use apelidos informais como o nome principal.
Passo 3. Forneça até 3 nomes alternativos, títulos ou apelidos pelos quais este personagem é conhecido em um array `aliases`. Inclua seu primeiro nome e sobrenome comuns se usados. IMPORTANTE: Se um sobrenome for compartilhado por vários personagens (ex: membros da família), NÃO o inclua como alias para nenhum dos personagens.
Step 4. Actively scan for up to {NUM_HIST} NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA LOCAIS:
Passo 1. Extraia de {NUM_LOCS} locais significativos. SEM SPOILERS: Pare exatamente na marca de %d%%.

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação após o progresso de leitura atual. Pare exatamente na marca de %d%%.
- As descrições devem refletir o estado dos personagens neste exato ponto do livro.

REGRAS ESTRITAS DE SEGURANÇA JSON:
- Você DEVE escapar corretamente todas as aspas duplas (\") dentro das strings.
- NÃO use quebras de linha não escapadas dentro das strings.
- Retorne APENAS um JSON válido e analisável.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nome Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel até o progresso atual",
      "gender": "Masculino / Feminino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Análise profunda com detalhes do texto até agora. SEM SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nome da Pessoa Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografia curta (MÁX {MAX_HIST_BIO} caracteres)",
      "importance_in_book": "Significância até o progresso atual",
      "context_in_book": "Como são mencionados (MÁX 100 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nome do Local", "description": "Descrição curta (MÁX {MAX_LOC_DESC} caracteres)"}
  ],
  "timeline": [
    {
      "chapter": "Título Exato do Capítulo das Amostras",
      "event": "Evento narrativo principal deste capítulo (Máx {MAX_TIMELINE_EVENT} caracteres)"
    }
  ]
} ]],

    -- Buscar mais personagens (Bypass do limite de IA)
    more_characters = [[Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Extraia EXATAMENTE 10 personagens importantes ADICIONAIS do texto.
Retorne APENAS um objeto JSON válido.

MANDATO DE CONCISÃO (CRÍTICO):
Para evitar o truncamento da resposta da IA, mantenha as descrições dos personagens com menos de {MAX_CHAR_DESC} caracteres.

INSTRUÇÃO CRÍTICA:
NÃO inclua nenhum dos seguintes personagens, pois eles já foram extraídos:
%s

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação após o progresso de leitura atual. Pare exatamente na marca de %d%%.
- As descrições devem refletir o estado dos personagens neste exato ponto do livro.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nome Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel até o progresso atual",
      "gender": "Masculino / Femenino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Análise profunda com detalhes do texto até agora. SEM SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[O usuário destacou a palavra "%s".
TAREFA: Determine si esta palavra é um Personagem, Local ou Figura Histórica no livro.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
Se a palavra NÃO for um personagem, local ou figura histórica no texto, defina `is_valid` como false.
 
FORMATO JSON OBRIGATÓRIO:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nome completo",
    "role": "Papel",
    "gender": "Masculino/Feminino/Desconocido",
    "occupation": "Ocupação",
    "description": "Breve descrição (máx. 250 caracteres)"
  },
  "error_message": ""
}
 
Nota: se o tipo for "location", o item deve ter "name" and "description". Si o tipo for "historical_figure", o item deve ter "name", "biography" e "role".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Breve explicação de por que isso não é um personagem nem um local."
}]],

    -- Strings de reserva (Fallback)
    fallback = {
        unknown_book = "Livro Desconhecido",
        unknown_author = "Autor Desconhecido",
        unnamed_character = "Personagem Sem Nome",
        not_specified = "Não Especificado",
        no_description = "Sem Descrição",
        unnamed_person = "Pessoa Sem Nome",
        no_biography = "Biografia Não Disponível"
    }
}
