# Relatório — Projeto de Banco de Dados

Disciplina: Projeto de Banco de Dados — 2026/2
UFF — Instituto de Computação — Prof. Marcos Bedo

> **Preencher antes de entregar:** nomes e matrículas dos integrantes do grupo.

---

## 1. Ajustes no modelo relacional

O modelo relacional fornecido no enunciado foi implementado com as alterações abaixo. Cada uma está marcada em `01_schema.sql` com um comentário `-- ALTERADO`.

### 1.1 Identificadores artificiais

No modelo original, a chave de `Video` tinha quatro atributos, um deles um `VARCHAR(200)`, e se propagava por `Participa`, `Comentario`, `Doacao` e pelas quatro especializações de pagamento, onde chegava a sete atributos. Os custos são três:

- índices de chave primária muito largos, com menos entradas por página e mais níveis de árvore B;
- junções caras, comparando sete colunas, duas delas textuais;
- redundância propagada, com `nome_canal` e `nro_plataforma` repetidos em dez tabelas.

Foram criados `id_usuario`, `id_canal`, `id_video` e `id_doacao`, e `Empresa.nro` e `Plataforma.nro` passaram a ser sequenciais (o enunciado já os descrevia como "número sequencial único"). Toda chave natural substituída foi preservada como `UNIQUE NOT NULL`, de modo que nenhuma restrição semântica se perdeu:

| Relação | Chave artificial | Chave natural preservada |
|---|---|---|
| `Usuario` | `id_usuario` | `UNIQUE (nick)` |
| `Canal` | `id_canal` | `UNIQUE (nro_plataforma, nome)` |
| `Video` | `id_video` | `UNIQUE (id_canal, dataH, titulo)` |
| `Doacao` | `id_doacao` | `UNIQUE (id_video, seq_comentario, seq_doacao)` |

O efeito mais visível está nas quatro especializações de pagamento, que passaram de sete colunas de chave para uma só. Em `Comentario`, a chave estrangeira para `Video` passou de quatro colunas (28 bytes mais o texto) para um `INTEGER`.

### 1.2 Chave de `Comentario`

O enunciado diz que o comentário tem "um número sequencial que depende do vídeo". O modelo fornecido colocava o usuário dentro da chave, o que permitiria repetir o mesmo `seq` no mesmo vídeo para usuários diferentes. A chave passou a ser `(id_video, seq)`, e `id_usuario` virou atributo não chave, `NOT NULL`.

Pela mesma razão o usuário saiu da chave de `Doacao`: o comentário já o determina funcionalmente, e mantê-lo violaria a 2FN em relação à chave escolhida.

### 1.3 Fusão de `EmpresaPais` em `Empresa`

`EmpresaPais` tinha `nro_empresa` como chave, ou seja, era uma decomposição 1:1 de `Empresa`. Uma decomposição 1:1 não remove redundância nem acrescenta poder expressivo; apenas força uma junção extra em toda consulta que precise do país ou do identificador nacional, que é o caso da consulta 5. Os atributos foram movidos para `Empresa`, preservando `UNIQUE (ddi_pais, id_nacional)`. A relação continua em BCNF.

`StreamerPais` **não** sofreu a mesma fusão, porque ali a tabela separada cumpre outro papel.

### 1.4 Especialização de streamer garantida pelo esquema

Tanto no modelo do enunciado quanto na primeira implementação do grupo, o dono do canal e os participantes do vídeo referenciavam `Usuario`, de modo que qualquer usuário comum poderia ser dono de canal. Como `StreamerPais` tem o streamer como chave, ela já é a tabela da especialização *Streamer*. As duas chaves estrangeiras passaram a apontar para `StreamerPais`, e a regra virou integridade referencial declarativa, sem custo de trigger.

Isso exigiu uma decisão: a chave de `StreamerPais` passou a ser apenas `id_streamer`, e não `(id_streamer, ddi_pais)`. O enunciado fala em "número de passaporte e país de passaporte", no singular, então um passaporte por streamer é a leitura direta do requisito — e é o que torna a tabela referenciável.

### 1.5 Outras correções

- **`NivelCanal.nome`**: o enunciado pede que "os nomes e os valores de cada nível" sejam definidos por canal, mas o atributo não existia. Acrescentado, com `UNIQUE (id_canal, nome)`.
- **`Canal.qtd_videos`**: o texto fala em "quantidade de vídeos postados" e o modelo só tinha `qtd_visualizacoes`. Os dois foram mantidos como derivados.
- **`Usuario.telefone`** passou a `NOT NULL`, por ser o telefone de validação em duas vias, e **`email`** ganhou `UNIQUE`.
- **`CartaoCredito.dataH`** foi incluído; o texto exige e o modelo omitia.
- **`MecanismoPlat.nro_plataforma`** foi removido: a plataforma é determinada pelo canal do vídeo do comentário. Armazená-la seria redundância e abriria espaço para inconsistência.
- **FK redundante em `Inscricao`**: a chave estrangeira para `Canal` saiu, porque a FK composta para `NivelCanal(id_canal, nivel)` já garante a existência do canal. Verificar as duas custaria duas buscas de índice por inserção sem ganho semântico.
- **`NivelCanal.gif`** é um caminho de arquivo em `VARCHAR(255)`, com `CHECK (gif LIKE '%.gif')`. Guardar milhares de binários no banco inflaria o *heap* e o TOAST sem benefício para nenhuma consulta pedida.
- **`CHECK (tipo IN ('privado','publico','misto'))`** sem acento, para não depender do encoding do cliente.
- **Políticas `ON DELETE`** definidas em todas as FKs, em cascata ao longo de canal → vídeo → comentário → doação → forma de pagamento. A exceção é `Comentario.id_usuario`, com `ON DELETE RESTRICT`: apagar um usuário não deve apagar o histórico de interação de um vídeo.

### 1.6 Normalização

O esquema está em BCNF: em cada relação o único determinante é a chave, primária ou candidata declarada como `UNIQUE`. Os dois pontos que exigiram atenção foram justamente os corrigidos acima — a dependência `comentário → usuário`, embutida na chave de `Doacao`, e a decomposição 1:1 de `EmpresaPais`.

`Plataforma.qtd_users`, `Canal.qtd_videos` e `Canal.qtd_visualizacoes` são desnormalização deliberada. Violam o princípio de não armazenar o que pode ser calculado, mas constam do enunciado e evitam agregações repetidas sobre as tabelas maiores. A consistência fica por conta das triggers, e `recalcular_derivados()` serve de rede de segurança.

### 1.7 Moedas

O enunciado define `fator_conver` como o fator de conversão para dólares, mas não diz em que moeda estão guardados os valores. A convenção adotada está documentada com `COMMENT ON COLUMN` no próprio catálogo:

| Valor | Moeda | Conversão |
|---|---|---|
| `Patrocinio.valor` | Dólares | nenhuma (o enunciado já define assim) |
| `Doacao.valor` | País de residência do doador | `valor * fator_conver` do doador |
| `NivelCanal.valor` | País de residência do dono do canal | `valor * fator_conver` do dono |

A conversão acontece sempre nas visões, nunca nas tabelas-base, para que uma eventual atualização de câmbio não exija reescrever dados históricos. Todas as consultas financeiras (4, 6, 7, 9, 10 e 11) apresentam valores em dólares, para que canais de países diferentes sejam comparáveis.

---

## 2. Triggers

| # | Trigger | Momento | Regra |
|---|---|---|---|
| T1 | `comentario_bi` / `comentario_bu` | `BEFORE` | Sequencial do comentário por vídeo e data não anterior à do vídeo |
| T2 | `video_data_bi` | `BEFORE` | Vídeo não anterior ao início do canal |
| T3 | `doacao_seq_bi` | `BEFORE INSERT` | Sequencial da doação dentro do comentário |
| T4 | `mecplat_seq_bi` | `BEFORE INSERT` | Sequencial do mecanismo próprio da plataforma |
| T5 | `*_subtipo_bi` (4) | `BEFORE` | Disjunção da especialização de pagamento |
| T6 | `doacao_total_ai` | `AFTER`, postergada | Totalidade da especialização de pagamento |
| T7 | `video_qtd_ai/ad/au` | `AFTER` | `qtd_videos` e `qtd_visualizacoes` do canal |
| T8 | `platusuario_qtd` | `AFTER` | `qtd_users` da plataforma |
| T9 | `participa_dono_bi` | `BEFORE` | O dono do canal não é registrado como convidado |
| T10 | `nivelcanal_cinco` / `canal_cinco_niveis` | `AFTER`, postergadas | Exatamente cinco níveis por canal |

### Justificativas

**T1, T3 e T4 — sequenciais dependentes.** O enunciado especifica números sequenciais que dependem de outra entidade. Uma `SEQUENCE` global não serve: daria números distintos a comentários de vídeos diferentes e deixaria buracos. As triggers calculam `MAX + 1` dentro do escopo correto, mas **só quando o atributo chega nulo**. O preenchimento condicional é essencial para a carga em massa: dentro de um mesmo `INSERT ... SELECT`, as linhas já inseridas não são visíveis ao *snapshot* usado pela trigger das linhas seguintes, e o `MAX` devolveria sempre o mesmo valor. A carga calcula os sequenciais com `row_number()` e os informa explicitamente; o caminho da trigger fica para inserções unitárias da aplicação.

O `FOR NO KEY UPDATE` sobre a linha pai serializa inserções concorrentes no mesmo escopo, evitando que duas transações simultâneas calculem o mesmo `MAX + 1`.

**T1 e T2 — consistência temporal.** São regras que envolvem duas tabelas e portanto não cabem em um `CHECK`, que no PostgreSQL só enxerga a própria linha.

**T5 e T6 — especialização disjunta e total.** As quatro formas de pagamento formam uma especialização disjunta e total da doação. A disjunção é verificada de imediato, no `BEFORE INSERT` de cada subclasse. A totalidade não pode ser: no instante em que a doação é inserida, a linha da subclasse ainda não existe. Por isso T6 é uma *constraint trigger* `DEFERRABLE INITIALLY DEFERRED`, avaliada só no `COMMIT`. É essa a razão de `03_carga.sql` rodar em uma transação única.

**T7 e T8 — atributos derivados, mantidos de forma incremental.** Em vez de recalcular por agregação a cada operação, as triggers somam e subtraem deltas (`qtd_videos + 1`, `qtd_visualizacoes + NEW.visu_total`). O custo por linha passa de uma agregação sobre o canal inteiro para um único `UPDATE` por chave primária. Isso importa porque a carga insere nove mil vídeos: a versão por agregação tornaria a inserção quadrática no número de vídeos por canal.

O efeito colateral é um `UPDATE` em `Canal` e `Plataforma` a cada inserção, o que gera muitas versões mortas de tupla. Por isso as duas tabelas foram criadas com `fillfactor = 70`, reservando espaço na própria página para a nova versão e permitindo atualização HOT, sem reescrever os índices. `Video` usa `fillfactor = 85` por ser atualizada com menos frequência.

**T9 — semântica de `Participa`.** O enunciado diz que o vídeo "pode ter a participação de mais streamers do que apenas o dono do canal". `Participa` registra portanto os convidados; o dono está em `Canal.id_streamer`. A trigger impede a dupla contagem.

**T10 — cardinalidade fixa.** O enunciado afirma que "existem cinco níveis de membros". Cardinalidade mínima não é expressável em DDL, e a verificação precisa ser postergada porque o canal e seus cinco níveis entram em comandos distintos. São duas triggers: uma sobre `NivelCanal`, que impede remover ou acrescentar níveis, e uma sobre `Canal`, que impede criar canal sem níveis.

### Custo das triggers na carga

As triggers são criadas **antes** da carga, de propósito: assim as mais de cinquenta mil tuplas inseridas passam por todas as validações, e os derivados saem corretos sem passo extra. Isso só é viável porque as triggers foram escritas para serem baratas — as de sequencial não executam nada quando o valor é informado, e as de derivados são incrementais. Para volumes muito maiores, a estratégia seria desabilitar as triggers de derivados durante a carga (`ALTER TABLE ... DISABLE TRIGGER`) e chamar `recalcular_derivados()` ao final, que existe exatamente para isso.

---

## 3. Visões

Cinco visões: duas materializadas e três virtuais. O critério foi direto: **virtual quando o ganho é de simplificação e o custo de recomputar é baixo; materializada quando é uma agregação pesada sobre as tabelas maiores, reaproveitada por várias consultas.**

### V1 — `mv_resumo_canal` (materializada)

Concentra tudo o que se agrega por canal: comentários online e offline, e as três fontes de receita já convertidas para dólares, com as respectivas contagens.

É a visão de maior retorno do projeto. Sozinha ela atende às consultas 3, 4, 7, 8, 9, 10 e 11. Sem ela, essas sete consultas repetiriam agregações independentes sobre `Patrocinio`, `Inscricao`, `Comentario` e `Doacao`, cada uma com junções próprias até `Conversao`. Concentrar tudo em uma estrutura também garante que as sete usem exatamente o mesmo critério de conversão de moeda — uma inconsistência aqui passaria despercebida se cada consulta fizesse a sua conta.

O resultado tem uma linha por canal, menos de dois mil registros contra dezenas de milhares nas tabelas de origem.

### V2 — `mv_interacoes_video` (materializada)

Comentários online, offline e total por vídeo, para a consulta 2.

Materializada porque a consulta é um ranking global: ordenar nove mil vídeos por contagem de comentários exigiria agregar `Comentario` inteira a cada chamada. Com a visão, o `ORDER BY ... DESC LIMIT k` lê diretamente o índice `idx_mv_interacoes_total`.

### V3 — `vw_streamer_plataforma` (virtual)

Canais, vídeos e visualizações por streamer e por plataforma, para a consulta 1.

Virtual porque lê apenas `Canal`, agregando os derivados que as triggers já mantêm. Nenhum acesso a `Video` é necessário, então o custo de recomputar é baixo. A granularidade `(streamer, plataforma)` permite responder tanto a consulta filtrada quanto a global por reagregação de um conjunto pequeno.

### V4 — `vw_patrocinio_empresa` (virtual)

Patrocínios vigentes com os dados da empresa, para a consulta 5.

Virtual porque é uma junção simples sem agregação, e porque a consulta 5 admite filtro por empresa: materializá-la obrigaria a varrer o resultado inteiro mesmo quando o filtro é muito seletivo. Mantida virtual, o otimizador empurra o predicado para dentro da junção.

### V5 — `vw_membro_usuario` (virtual)

Quantidade de canais e desembolso mensal em dólares por membro, para a consulta 6.

Virtual pelo mesmo motivo de V4: a consulta normalmente é chamada para um usuário específico, e `idx_inscricao_membro` torna esse caminho barato.

### Atualização

As duas materializadas têm índice `UNIQUE`, o que habilita `REFRESH MATERIALIZED VIEW CONCURRENTLY` — atualização sem bloquear leituras.

`atualizar_visoes()` usa o refresh **bloqueante**, e não o concorrente. A razão é técnica: `REFRESH ... CONCURRENTLY` não pode ser executado dentro de um bloco de transação, e toda função PL/pgSQL roda dentro de uma. A variante concorrente está documentada no README para uso direto no `psql`.

O custo é o dado desatualizado entre refreshes. Para este domínio isso é aceitável: as consultas são rankings analíticos, não operação em tempo real, e um ranking de faturamento calculado há alguns minutos continua válido para decisão. Disparar o refresh por trigger a cada doação foi descartado: transformaria cada inserção em uma recomputação completa, invertendo exatamente o ganho que a visão materializada existe para obter.

### Organização física

As duas materializadas foram reorganizadas com `CLUSTER` pela coluna que suas consultas usam para ordenar ou filtrar: `nro_plataforma` em `mv_resumo_canal` e `total_comentarios DESC` em `mv_interacoes_video`. Com as linhas fisicamente próximas na ordem de leitura, as consultas top-k e os filtros por plataforma leem menos páginas. `CLUSTER` é uma reorganização pontual, não mantida automaticamente, por isso `atualizar_visoes(TRUE)` permite refazê-la após um refresh.

---

## 4. Índices

O PostgreSQL cria índice automaticamente para `PRIMARY KEY` e `UNIQUE`, mas **não** para chave estrangeira. A análise partiu daí: procuramos colunas usadas em filtro ou junção que não estivessem cobertas, nem como prefixo, por um índice existente.

| # | Índice | Consultas | Por que é necessário |
|---|---|---|---|
| I1 | `idx_canal_streamer` — hash em `Canal(id_streamer)` | 3 | FK sem índice; a `UNIQUE` existente começa por `nro_plataforma` |
| I2 | `idx_canal_plataforma` — btree em `Canal(nro_plataforma) INCLUDE (id_canal, id_streamer)` | 1, 12 | A coluna já é prefixo da `UNIQUE`; o ganho aqui é o `INCLUDE` |
| I3 | `idx_patrocinio_canal` — btree em `Patrocinio(id_canal) INCLUDE (valor)` | 8, 11 | A PK começa por `nro_empresa` |
| I4 | `idx_inscricao_membro` — btree em `Inscricao(id_membro) INCLUDE (id_canal, nivel)` | 6 | A PK começa por `id_canal` |
| I5 | `idx_doacao_efetivada` — btree parcial em `Doacao(id_video, seq_comentario) INCLUDE (valor) WHERE status IN ('recebido','lido')` | 4, 7, 10, 11 | Evita ler as doações recusadas |

### Observações

**Índice hash em I1.** `Canal.id_streamer` só aparece em comparações de igualdade, nunca em faixa ou ordenação. Um índice hash é menor que o B-tree equivalente, e desde o PostgreSQL 10 é *crash-safe* e replicado. É o caso de uso exato para o qual ele existe.

**`INCLUDE` em I2, I3 e I4.** As colunas adicionais não participam da busca, mas permitem *index-only scan*: a consulta é respondida sem visitar o *heap*. O custo é um índice um pouco maior.

**Índice parcial em I5.** Indexa apenas as doações efetivadas, que são cerca de 92% da tabela na carga atual. O ganho não é tanto de tamanho quanto de semântica: o predicado de status não precisa ser reavaliado, e uma doação recusada não gera manutenção do índice. É o índice que mais importa para o *refresh* de `mv_resumo_canal`, a operação periódica mais cara do sistema.

**O que foi deliberadamente não indexado.** `Comentario(id_video)` seria redundante: é prefixo da PK `(id_video, seq)`. `Video(id_canal)` também, coberto pelo prefixo da `UNIQUE (id_canal, dataH, titulo)`. Criá-los só adicionaria custo de manutenção sem mudar nenhum plano.

**Overhead de inserção.** As tabelas que mais recebem inserções no domínio são `Comentario` e `Doacao`. Nenhum dos cinco índices onera `Comentario`, e apenas I5 onera `Doacao` — parcialmente. Os outros quatro recaem sobre `Canal`, `Patrocinio` e `Inscricao`, de escrita muito menos frequente. A distribuição foi intencional: o enunciado pede explicitamente que se considere o custo de inserção, e concentrar índices na tabela mais volumosa seria a decisão errada.

Os índices das visões materializadas não foram contados no limite de cinco: os `UNIQUE` são pré-requisito do `REFRESH CONCURRENTLY` e os demais apoiam a ordenação interna das próprias visões, não as tabelas-base.

---

## 5. Consultas

As doze consultas são *functions* PL/pgSQL com `RETURNS TABLE`. A escolha de `FUNCTION` em vez de `PROCEDURE` é técnica: no PostgreSQL uma `PROCEDURE` não devolve conjunto de linhas de forma utilizável em `SELECT ... FROM`, enquanto uma função com `RETURNS TABLE` é consultável como se fosse tabela.

### Filtros opcionais com ramos separados

Os filtros opcionais foram implementados com `IF ... ELSE` e duas consultas completas, e não com o padrão compacto `(p_x IS NULL OR coluna = p_x)`.

A diferença é de desempenho. Com o predicado disjuntivo, o otimizador precisa gerar um único plano que sirva para os dois casos, e como `p_x IS NULL` pode ser verdadeiro ele não consegue usar o índice sobre a coluna: o resultado é varredura sequencial mesmo quando o filtro é muito seletivo. Com os ramos separados, cada consulta é otimizada isoladamente, e o ramo filtrado recebe um plano com acesso indexado.

O custo é duplicar o texto da consulta. Em troca, o caminho mais comum — filtrar por um streamer, por um canal, por um usuário — fica muito mais barato.

### Parâmetros por nome, não por identificador

Identificador artificial é bom para o banco e ruim para quem consulta: ninguém sabe o `id_canal` de cor. As funções 2, 3, 6 e 7 recebem o nome do canal ou o nick do usuário e resolvem o identificador internamente, com os auxiliares `id_do_canal()` e `id_do_usuario()`.

`id_do_canal()` usa `SELECT ... INTO STRICT` e trata as duas exceções possíveis: `no_data_found`, quando o nome não existe, e `too_many_rows`, quando o mesmo nome aparece em mais de uma plataforma — nesse caso a mensagem pede que se informe também o número da plataforma. É a consequência direta de o canal ser identificado por `(nome, plataforma)`, e a função a expõe de forma legível em vez de falhar com um erro genérico.

### Resolução de ambiguidade

Todas as funções usam `#variable_conflict use_column`, que resolve o conflito entre os nomes das colunas de saída declaradas em `RETURNS TABLE` e as colunas homônimas das tabelas consultadas.

### Interpretações

**Consulta 1.** "Streamers que possuem a maior quantidade de vídeos publicados" foi lido como os vídeos **dos canais dos quais o streamer é dono**, não os vídeos em que ele aparece como convidado. `Participa` registra participação, não autoria.

**Consulta 4.** "Valor médio das doações recebidas por comentário" foi calculado como o total arrecadado dividido pelo número de comentários **que trouxeram doação**, e não por todos os comentários do canal. A segunda leitura mediria engajamento, não ticket médio.

**Consultas 4, 7, 9, 10 e 11.** Doações com status `recusado` são excluídas: não representam receita efetiva e distorceriam os rankings. `recebido` e `lido` entram.

**Consulta 12.** O enunciado pede ordenar as plataformas "pela quantidade de streamers E canais". Como são duas grandezas, a função devolve as duas colunas separadas e ordena pela soma, apresentando esse total em uma coluna explícita para que o critério fique visível no resultado.

---

## 6. Carga de dados

A base tem entre 1.000 e 10.000 tuplas por tabela, conforme o item mandatório 1. A contagem é impressa ao final de `03_carga.sql`.

Duas decisões merecem registro.

**Dados realistas.** Moedas reais com fatores de conversão plausíveis, DDIs e nomes de países reais, jogos reais, e as plataformas 1 a 8 fixas (YouTube, Twitch, Kick e outras). Tabelas naturalmente pequenas — `Conversao`, `Pais`, `Plataforma` — foram completadas com registros fictícios até atingir as mil tuplas exigidas.

**Distribuições enviesadas.** Vídeos, comentários, inscrições e patrocínios são sorteados com `power(random(), n)`, o que concentra a massa em poucos canais e poucos usuários, como acontece no domínio real. Isso importa para a avaliação: com dados uniformes, todo canal teria praticamente o mesmo número de vídeos e de doações, os rankings das consultas 8 a 11 seriam arbitrários, e os índices não mostrariam diferença de desempenho — não haveria o que medir nem o que justificar.

A carga usa `setseed(0.2026)` e é portanto reprodutível: duas execuções geram exatamente a mesma base, o que torna as medições comparáveis entre máquinas.

---

## 7. Medições de desempenho

> **Preencher com os resultados obtidos na máquina do grupo.** O README traz os comandos; o procedimento é medir a consulta com `EXPLAIN (ANALYZE, BUFFERS)`, remover o índice dentro de uma transação, repetir a medição e fazer `ROLLBACK`.

| Consulta | Sem índice (ms) | Com índice (ms) | Ganho | Mudança no plano |
|---|---|---|---|---|
| 3 — interações, filtrada por streamer (I1) | | | | |
| 1 — top streamers, filtrada por plataforma (I2) | | | | |
| 8 — top patrocínio (I3) | | | | |
| 6 — gasto de um membro (I4) | | | | |
| `atualizar_visoes()` (I5) | | | | |

| Operação | Sem visão materializada (ms) | Com visão materializada (ms) | Ganho |
|---|---|---|---|
| Consulta 2 — vídeos mais comentados | | | |
| Consulta 11 — top faturamento | | | |

Também vale medir: o tempo de `03_carga.sql` com e sem as triggers ativas, e o tempo de `atualizar_visoes()` contra o de `REFRESH ... CONCURRENTLY`.

---

## 8. Pontos em aberto

Decisões tomadas por interpretação do enunciado, a confirmar com o professor:

1. **Doações por comentário.** O modelo ER mostra a relação `doa` como 1:1, enquanto o texto sugere um sequencial de doações dentro do comentário. O esquema aceita várias; a carga gera uma na maioria dos casos e duas em cerca de 8%.
2. **Moeda de armazenamento** dos valores de doação e de nível de membro, conforme a seção 1.7.
3. **Tabelas pequenas** completadas com dados fictícios para atingir o mínimo de mil tuplas.
4. **Exatamente cinco níveis por canal**, garantido por T10. Se o requisito admitir canais com menos níveis, basta remover as duas triggers.
5. **Escopo do sequencial do mecanismo próprio da plataforma.** Implementado no escopo do comentário, já que o comentário determina tanto o usuário quanto a plataforma citados no enunciado.
6. **Um passaporte por streamer**, decorrente da leitura literal do requisito e necessário para que `StreamerPais` seja referenciável (seção 1.4).
