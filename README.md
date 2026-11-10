# Trabalho Final — Projeto de Banco de Dados (2026/2)

Base de dados para catalogar streamers de jogos online, implementada em PostgreSQL.

UFF — Instituto de Computação — Prof. Marcos Bedo

## Requisitos

- PostgreSQL 11 ou superior, com o cliente `psql`. Os scripts usam `GENERATED ALWAYS AS IDENTITY`, `COUNT(...) FILTER (...)` e a cláusula `INCLUDE` em índices.
- Os scripts usam comandos do próprio `psql` (`\set ON_ERROR_STOP on`), então devem ser executados por ele, e não pelo Query Tool do pgAdmin.

## Como reproduzir

```bash
createdb streamers
cd sql
psql -d streamers -f 01_schema.sql
psql -d streamers -f 02_triggers.sql
psql -d streamers -f 03_carga.sql
psql -d streamers -f 04_visoes.sql
psql -d streamers -f 05_indices.sql
psql -d streamers -f 06_funcoes.sql
```

Se o servidor exigir usuário e senha, acrescente `-U usuario -h localhost`.

Não use a opção `-1` (`--single-transaction`): o `03_carga.sql` termina com `VACUUM FULL`, que não roda dentro de uma transação.

Todos os scripts começam com `DROP ... IF EXISTS`, então podem ser reexecutados sem recriar o banco. Para começar do zero mesmo assim:

```bash
dropdb streamers && createdb streamers
```

### Por que esta ordem

| Posição | Motivo |
|---|---|
| Triggers **antes** da carga | Os dados entram validados, e os atributos derivados são calculados durante a inserção. As triggers de sequencial só agem quando o valor chega nulo, e as de derivados são incrementais, então o custo na carga é baixo. |
| Índices **depois** da carga | Construir o índice sobre a tabela pronta é mais rápido do que mantê-lo a cada `INSERT`, e evita o overhead de inserção que o enunciado pede para considerar. |
| Visões **depois** da carga | As materializadas são populadas no momento da criação. |
| Funções por último | Dependem das visões. |

O `03_carga.sql` roda dentro de uma única transação porque duas regras são verificadas por *constraint triggers* postergadas (`DEFERRABLE INITIALLY DEFERRED`), avaliadas só no `COMMIT`: a totalidade da especialização de doação e a exigência de cinco níveis por canal.

A carga usa `setseed(0.2026)`, então gera exatamente a mesma base em toda execução, o que torna as medições de desempenho comparáveis. Ao final, o script imprime a contagem de tuplas de cada tabela — todas ficam entre 1.000 e 10.000.

## Consultas

Os filtros são opcionais e usam nomes, não identificadores internos: nick do usuário, nome do canal, nro da plataforma e nro da empresa.

| Nº | Função | Filtro opcional |
|---|---|---|
| 1 | `streamers_mais_videos(p_plataforma, p_k)` | nro da plataforma |
| 2 | `videos_mais_comentados(p_canal, p_plataforma, p_k)` | nome do canal |
| 3 | `canais_por_interacoes(p_streamer, p_k)` | nick do streamer |
| 4 | `canais_por_media_doacao(p_plataforma, p_k)` | nro da plataforma |
| 5 | `patrocinios_por_empresa(p_empresa)` | nro da empresa |
| 6 | `gasto_dos_membros(p_usuario)` | nick do usuário |
| 7 | `canais_com_doacao(p_canal, p_plataforma)` | nome do canal |
| 8 | `top_canais_patrocinio(p_k)` | |
| 9 | `top_canais_membros(p_k)` | |
| 10 | `top_canais_doacoes(p_k)` | |
| 11 | `top_canais_faturamento(p_k)` | |
| 12 | `top_plataformas(p_k, p_plataforma)` | nro da plataforma |

Nas consultas 2 e 7, `p_plataforma` só é necessário quando existe canal com o mesmo nome em mais de uma plataforma; a função avisa quando isso acontece.

```sql
-- sem filtro
SELECT * FROM streamers_mais_videos();
SELECT * FROM videos_mais_comentados();
SELECT * FROM canais_por_interacoes();
SELECT * FROM canais_por_media_doacao();
SELECT * FROM patrocinios_por_empresa();
SELECT * FROM gasto_dos_membros();
SELECT * FROM canais_com_doacao();
SELECT * FROM top_canais_patrocinio(10);
SELECT * FROM top_canais_membros(10);
SELECT * FROM top_canais_doacoes(10);
SELECT * FROM top_canais_faturamento(10);
SELECT * FROM top_plataformas(10);

-- com filtro (as plataformas 1 a 8 são fixas: 1 é o YouTube, 2 a Twitch, 3 a Kick)
SELECT * FROM streamers_mais_videos(1);
SELECT * FROM canais_por_media_doacao(2, 20);
SELECT * FROM patrocinios_por_empresa(42);
SELECT * FROM top_plataformas(1, 2);
```

Os nicks e os nomes de canal são sorteados na carga. Para obter valores válidos:

```sql
SELECT c.nome AS canal, c.nro_plataforma, u.nick AS streamer
FROM Canal c JOIN Usuario u ON u.id_usuario = c.id_streamer
ORDER BY c.qtd_videos DESC LIMIT 5;

SELECT u.nick AS membro
FROM Inscricao i JOIN Usuario u ON u.id_usuario = i.id_membro LIMIT 5;
```

E então:

```sql
SELECT * FROM videos_mais_comentados('nome do canal');
SELECT * FROM canais_com_doacao('nome do canal', 1);
SELECT * FROM canais_por_interacoes('nick do streamer');
SELECT * FROM gasto_dos_membros('nick do membro');
```

## Atualização dos dados derivados

As consultas 2, 3, 4 e 7 a 11 leem visões materializadas. Depois de inserir, alterar ou remover dados é preciso atualizá-las:

```sql
SELECT atualizar_visoes();        -- refresh + ANALYZE
SELECT atualizar_visoes(TRUE);    -- também refaz o CLUSTER
```

`REFRESH MATERIALIZED VIEW CONCURRENTLY` **não pode ser executado dentro de uma função**, porque funções rodam sempre dentro de uma transação. Por isso `atualizar_visoes()` usa o refresh bloqueante. Os índices `UNIQUE` das materializadas existem para permitir a variante concorrente, que deve ser chamada direto no `psql`:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_resumo_canal;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_interacoes_video;
```

`qtd_videos`, `qtd_visualizacoes` e `qtd_users` são mantidos por trigger e não precisam de refresh. Se alguma carga for feita com as triggers desabilitadas, use a rede de segurança:

```sql
SELECT recalcular_derivados();
```

## Medição de desempenho

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM canais_por_interacoes('nick do streamer');

-- compara o plano sem um índice, sem removê-lo de verdade
BEGIN;
DROP INDEX idx_canal_streamer;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM canais_por_interacoes('nick do streamer');
ROLLBACK;
```

`EXPLAIN` sobre uma chamada de função mostra apenas o nó `Function Scan`. Para ver o plano interno:

```sql
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 0;
SET auto_explain.log_nested_statements = on;
SET auto_explain.log_analyze = on;
```

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `sql/01_schema.sql` | As 19 tabelas, com identificadores artificiais, `UNIQUE`, `NOT NULL`, `CHECK`, políticas `ON DELETE` e `fillfactor` |
| `sql/02_triggers.sql` | 10 regras de consistência e a função `recalcular_derivados()` |
| `sql/03_carga.sql` | Carga de dados artificiais com semente fixa |
| `sql/04_visoes.sql` | 2 visões materializadas, 3 virtuais e a função `atualizar_visoes()` |
| `sql/05_indices.sql` | Os 5 índices de apoio nas tabelas-base |
| `sql/06_funcoes.sql` | As 12 consultas e os dois resolvedores de nome |
| `modelo_relacional.md` | Modelo relacional implementado |
| `relatorio.md` | Justificativa das escolhas de implementação |
