# Trabalho Final - Projeto de Banco de Dados (2026/2)

Base de dados de streamers de jogos online, implementada em PostgreSQL.

## Requisitos

- PostgreSQL com o cliente `psql` (testado na versão 18).

Os scripts usam comandos do `psql` (`\set`), por isso devem ser executados por ele, e não pelo Query Tool do pgAdmin.

## Como reproduzir

Crie um banco vazio e rode os cinco scripts da pasta `sql`, nesta ordem:

```bash
createdb streamers
cd sql
psql -d streamers -f 01_schema.sql
psql -d streamers -f 02_carga.sql
psql -d streamers -f 03_triggers.sql
psql -d streamers -f 04_visoes.sql
psql -d streamers -f 05_funcoes.sql
```

Se o servidor exigir usuário e senha, acrescente `-U usuario -h localhost` aos comandos.

Não use a opção `-1` (`--single-transaction`): o `02_carga.sql` executa `VACUUM FULL`, que não roda dentro de transação.

A ordem importa. A carga é feita antes da criação dos triggers e dos índices de apoio para que a inserção em massa não pague esse custo.

Ao final do `02_carga.sql` é exibida a quantidade de tuplas de cada tabela. Os dados são sorteados com semente fixa, então a carga é a mesma em toda execução.

Para refazer tudo do zero:

```bash
dropdb streamers
createdb streamers
```

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `01_schema.sql` | As 20 tabelas do modelo relacional, com identificadores artificiais, `UNIQUE`, `NOT NULL` e `CHECK` |
| `02_carga.sql` | Carga de dados artificiais |
| `03_triggers.sql` | Triggers de consistência e a função `recalcular_derivados()` |
| `04_visoes.sql` | 2 visões materializadas, 3 visões virtuais, os 5 índices de apoio e a função `atualizar_visoes()` |
| `05_funcoes.sql` | As 12 consultas do enunciado, como functions |

## Consultas

Os filtros opcionais podem ser omitidos. Eles usam as chaves do modelo: nro da plataforma, nro da empresa, nick do usuário e nome do canal.

| Nº | Função | Filtro opcional |
|---|---|---|
| 1 | `streamers_mais_videos(p_plataforma)` | nro da plataforma |
| 2 | `videos_mais_comentados(p_canal, p_plataforma)` | nome do canal |
| 3 | `canais_por_interacoes(p_streamer)` | nick do streamer |
| 4 | `canais_por_media_doacao(p_plataforma)` | nro da plataforma |
| 5 | `patrocinios_por_empresa(p_empresa)` | nro da empresa |
| 6 | `gasto_dos_membros(p_usuario)` | nick do usuário |
| 7 | `canais_com_doacao(p_canal, p_plataforma)` | nome do canal |
| 8 | `top_canais_patrocinio(p_k)` | |
| 9 | `top_canais_membros(p_k)` | |
| 10 | `top_canais_doacoes(p_k)` | |
| 11 | `top_canais_faturamento(p_k)` | |
| 12 | `top_plataformas(p_k, p_plataforma)` | nro da plataforma |

Nas consultas 2 e 7, `p_plataforma` só é necessário quando existe canal com o mesmo nome em mais de uma plataforma, já que o canal é identificado por (nome, plataforma).

Exemplos sem filtro:

```sql
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
```

Exemplos com filtro (a plataforma 1 é o YouTube e a 2 é a Twitch):

```sql
SELECT * FROM streamers_mais_videos(1);
SELECT * FROM canais_por_media_doacao(2);
SELECT * FROM patrocinios_por_empresa(3);
SELECT * FROM top_plataformas(1, 2);
```

Os nicks e os nomes de canal são sorteados na carga. Para pegar valores válidos para os outros filtros:

```sql
SELECT c.nome AS canal, c.nro_plataforma, u.nick AS streamer
FROM Canal c JOIN Usuario u ON u.id_usuario = c.id_streamer
ORDER BY c.qtd_videos DESC LIMIT 5;

SELECT u.nick AS membro
FROM Inscricao i JOIN Usuario u ON u.id_usuario = i.id_membro
LIMIT 5;
```

E então, trocando pelos valores retornados:

```sql
SELECT * FROM videos_mais_comentados('nome do canal');
SELECT * FROM canais_com_doacao('nome do canal', 1);
SELECT * FROM canais_por_interacoes('nick do streamer');
SELECT * FROM gasto_dos_membros('nick do membro');
```

## Atualização dos dados derivados

As consultas 2, 3, 4 e 7 a 11 leem as visões materializadas. Depois de inserir, alterar ou remover dados, é preciso atualizá-las para que as mudanças apareçam:

```sql
SELECT recalcular_derivados();   -- qtd_users das plataformas e qtd_visualizacoes dos canais
SELECT atualizar_visoes();       -- visões materializadas, sem bloquear leituras
SELECT atualizar_visoes(TRUE);   -- também refaz o CLUSTER (bloqueia as visões enquanto roda)
```
