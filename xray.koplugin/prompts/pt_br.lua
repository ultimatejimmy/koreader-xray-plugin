return {
    -- Instrução do sistema
    system_instruction = "Você é um pesquisador literário especialista. Sua resposta deve estar APENAS no formato JSON válido. Certifique-se de que os dados sejam altamente precisos e pertençam estritamente ao contexto fornecido.",

    -- Mensagem apenas para o autor (Para busca rápida de biografia)
    author_only = [[Identifique e forneça a biografia do autor do livro "%s". 
Os metadatos sugerem que o autor é "%s", mas verifique isso com base no título do livro.

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

ALGORITMO PARA CRONOLOGIA (PRIORIDADE MÁXIMA):
Você sofre de viés de recência. Para evitar pular capítulos ou combiná-los, você DEVE executar este loop exato:
Passo 1. Olhe APENAS para o bloco "CHAPTER SAMPLES". Conte os capítulos narrativos.
Passo 2. Comece no primeiríssimo capítulo das amostras. Crie EXATAMENTE UM objeto de evento no array `timeline`.
Passo 3. O campo `chapter` DEVE corresponder exatamente ao cabeçalho do capítulo na amostra. (NOTA: Se este for um omnibus contendo vários livros, os títulos dos capítulos podem se repetir ou reiniciar. Mapeie-os estritamente na ordem sequencial fornecida).
Passo 4. Resuma esse capítulo específico no campo `event` (Máximo 200 caracteres).
Passo 5. Vá para o PRÓXIMO capítulo nas amostras e repita o Passo 2.
Passo 6. NÃO pare até que CADA capítulo nas amostras tenha EXATAMENTE UM evento correspondente. Não os agrupe. SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA PERSONAGENS E FIGURAS HISTÓRICAS:
Passo 1. Extraia de 15 a 25 personagens importantes usando ambos os blocos de texto.
Passo 2. Você DEVE usar seus nomes completos e formais (ex: "Abraham Van Helsing"). NÃO use apelidos informais como o nome principal.
Passo 3. Escaneie ativamente por pessoas REAIS da história humana (ex: Presidentes, Autores, Generais). Adicione-os em `historical_figures`.
SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA LOCAIS:
Passo 1. Extraia de 5 a 10 locais significativos. SEM SPOILERS: Pare exatamente na marca de %d%%.

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
      "role": "Papel até o progresso atual",
      "gender": "Masculino / Feminino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Análise profunda (250-300 caracteres). SEM SPOILERS."
    }
  ],
  "historical_figures": [
    {
      "name": "Nome da Pessoa Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografia curta (MÁX 150 caracteres)",
      "importance_in_book": "Significância até o progresso atual",
      "context_in_book": "Como são mencionados"
    }
  ],
  "locations": [
    {"name": "Nome do Local", "description": "Descrição curta (MÁX 150 caracteres)"}
  ],
  "timeline": [
    {
      "chapter": "Título Exato do Capítulo das Amostras",
      "event": "Evento narrativo principal deste capítulo (MÁX 150 caracteres)"
    }
  ]
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
