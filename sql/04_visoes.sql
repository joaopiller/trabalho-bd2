\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP MATERIALIZED VIEW IF EXISTS mv_interacoes_video, mv_resumo_canal;
DROP VIEW IF EXISTS vw_streamer_plataforma, vw_patrocinio_empresa, vw_membro_usuario;

-- V1 (materializada): tudo o que se agrega por canal — interacoes e as tres
-- fontes de receita, ja convertidas para dolares. Atende as consultas 3, 4, 7,
-- 8, 9, 10 e 11 com uma unica estrutura e um unico criterio de conversao.
CREATE MATERIALIZED VIEW mv_resumo_canal AS
SELECT c.id_canal,
       c.nome,
       c.nro_plataforma,
       c.id_streamer,
       c.qtd_videos,
       COALESCE(p.total_usd, 0)                                   AS patrocinio_usd,
       COALESCE(p.qtd, 0)                                         AS qtd_patrocinadores,
       COALESCE(m.qtd, 0)                                         AS qtd_membros,
       COALESCE(m.total_usd, 0)                                   AS membros_usd_mes,
       COALESCE(i.qtd_on, 0)                                      AS coment_online,
       COALESCE(i.qtd_off, 0)                                     AS coment_offline,
       COALESCE(i.qtd_on, 0) + COALESCE(i.qtd_off, 0)             AS interacoes,
       COALESCE(d.qtd, 0)                                         AS qtd_doacoes,
       COALESCE(d.qtd_coment, 0)                                  AS coment_com_doacao,
       COALESCE(d.total_usd, 0)                                   AS doacoes_usd,
       COALESCE(p.total_usd, 0) + COALESCE(m.total_usd, 0)
                                + COALESCE(d.total_usd, 0)        AS receita_usd
FROM Canal c
LEFT JOIN (
    SELECT pa.id_canal, COUNT(*) AS qtd, SUM(pa.valor) AS total_usd
    FROM Patrocinio pa
    GROUP BY pa.id_canal
) p ON p.id_canal = c.id_canal
LEFT JOIN (
    SELECT i.id_canal,
           COUNT(*) AS qtd,
           SUM(ROUND(n.valor * cv.fator_conver, 2)) AS total_usd
    FROM Inscricao i
    JOIN NivelCanal n ON n.id_canal   = i.id_canal AND n.nivel = i.nivel
    JOIN Canal ca     ON ca.id_canal  = i.id_canal
    JOIN Usuario dono ON dono.id_usuario = ca.id_streamer
    JOIN Pais pd      ON pd.DDI       = dono.pais_residencia
    JOIN Conversao cv ON cv.moeda     = pd.moeda
    GROUP BY i.id_canal
) m ON m.id_canal = c.id_canal
LEFT JOIN (
    SELECT v.id_canal,
           COUNT(*) FILTER (WHERE co.coment_on)     AS qtd_on,
           COUNT(*) FILTER (WHERE NOT co.coment_on) AS qtd_off
    FROM Comentario co
    JOIN Video v ON v.id_video = co.id_video
    GROUP BY v.id_canal
) i ON i.id_canal = c.id_canal
LEFT JOIN (
    SELECT v.id_canal,
           COUNT(*)                                        AS qtd,
           COUNT(DISTINCT (d.id_video, d.seq_comentario))  AS qtd_coment,
           SUM(ROUND(d.valor * cv.fator_conver, 2))        AS total_usd
    FROM Doacao d
    JOIN Video v      ON v.id_video    = d.id_video
    JOIN Comentario co ON co.id_video  = d.id_video AND co.seq = d.seq_comentario
    JOIN Usuario u    ON u.id_usuario  = co.id_usuario
    JOIN Pais pa      ON pa.DDI        = u.pais_residencia
    JOIN Conversao cv ON cv.moeda      = pa.moeda
    WHERE d.status IN ('recebido', 'lido')
    GROUP BY v.id_canal
) d ON d.id_canal = c.id_canal;

CREATE UNIQUE INDEX uq_mv_resumo_canal      ON mv_resumo_canal USING btree (id_canal);
CREATE INDEX        idx_mv_resumo_streamer  ON mv_resumo_canal USING hash  (id_streamer);
CREATE INDEX        idx_mv_resumo_plat      ON mv_resumo_canal USING btree (nro_plataforma);
CLUSTER mv_resumo_canal USING idx_mv_resumo_plat;

-- V2 (materializada): comentarios online, offline e total por video (consulta 2).
CREATE MATERIALIZED VIEW mv_interacoes_video AS
SELECT v.id_video,
       v.id_canal,
       c.nome AS canal,
       c.nro_plataforma,
       v.titulo,
       v.dataH,
       COUNT(co.seq) FILTER (WHERE co.coment_on)     AS coment_online,
       COUNT(co.seq) FILTER (WHERE NOT co.coment_on) AS coment_offline,
       COUNT(co.seq)                                 AS total_comentarios
FROM Video v
JOIN Canal c ON c.id_canal = v.id_canal
LEFT JOIN Comentario co ON co.id_video = v.id_video
GROUP BY v.id_video, v.id_canal, c.nome, c.nro_plataforma, v.titulo, v.dataH;

CREATE UNIQUE INDEX uq_mv_interacoes_video  ON mv_interacoes_video USING btree (id_canal, id_video);
CREATE INDEX        idx_mv_interacoes_total ON mv_interacoes_video USING btree (total_comentarios DESC);
CLUSTER mv_interacoes_video USING idx_mv_interacoes_total;

-- V3 (virtual): producao por streamer e plataforma (consulta 1). Le apenas os
-- derivados ja mantidos em Canal, sem tocar em Video.
CREATE VIEW vw_streamer_plataforma AS
SELECT c.id_streamer,
       c.nro_plataforma,
       COUNT(*)                      AS qtd_canais,
       SUM(c.qtd_videos)             AS qtd_videos,
       SUM(c.qtd_visualizacoes)      AS qtd_visualizacoes
FROM Canal c
GROUP BY c.id_streamer, c.nro_plataforma;

-- V4 (virtual): patrocinios vigentes com os dados da empresa (consulta 5).
CREATE VIEW vw_patrocinio_empresa AS
SELECT e.nro AS nro_empresa,
       e.nome AS empresa,
       e.nome_fantasia,
       c.id_canal,
       c.nome AS canal,
       c.nro_plataforma,
       p.valor AS valor_usd
FROM Patrocinio p
JOIN Empresa e ON e.nro      = p.nro_empresa
JOIN Canal c   ON c.id_canal = p.id_canal;

-- V5 (virtual): desembolso mensal de cada membro, em dolares (consulta 6).
CREATE VIEW vw_membro_usuario AS
SELECT u.id_usuario,
       u.nick,
       COUNT(*)                                  AS qtd_canais,
       SUM(ROUND(n.valor * cv.fator_conver, 2))  AS total_mensal_usd
FROM Inscricao i
JOIN NivelCanal n ON n.id_canal      = i.id_canal AND n.nivel = i.nivel
JOIN Usuario u    ON u.id_usuario    = i.id_membro
JOIN Canal ca     ON ca.id_canal     = i.id_canal
JOIN Usuario dono ON dono.id_usuario = ca.id_streamer
JOIN Pais pd      ON pd.DDI          = dono.pais_residencia
JOIN Conversao cv ON cv.moeda        = pd.moeda
GROUP BY u.id_usuario, u.nick;

-- REFRESH ... CONCURRENTLY nao pode rodar dentro de um bloco de transacao, e
-- toda funcao roda dentro de um. Por isso a rotina usa o refresh bloqueante.
-- Os indices UNIQUE acima permitem a variante concorrente fora da funcao:
--     REFRESH MATERIALIZED VIEW CONCURRENTLY mv_resumo_canal;
CREATE OR REPLACE FUNCTION atualizar_visoes(p_reorganizar BOOLEAN DEFAULT FALSE) RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_resumo_canal;
    REFRESH MATERIALIZED VIEW mv_interacoes_video;
    IF p_reorganizar THEN
        CLUSTER mv_resumo_canal;
        CLUSTER mv_interacoes_video;
    END IF;
    ANALYZE mv_resumo_canal;
    ANALYZE mv_interacoes_video;
END;
$$ LANGUAGE plpgsql;

ANALYZE mv_resumo_canal;
ANALYZE mv_interacoes_video;
