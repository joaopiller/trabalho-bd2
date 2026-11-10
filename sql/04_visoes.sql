\set ON_ERROR_STOP on

DROP MATERIALIZED VIEW IF EXISTS mv_interacoes_video;
DROP MATERIALIZED VIEW IF EXISTS mv_resumo_canal;
DROP VIEW IF EXISTS vw_streamer_plataforma, vw_patrocinio_empresa, vw_membro_usuario;

-- resumo por canal: patrocínio, membros, comentários e doações já em dólar (consultas 3, 4 e 7 a 11)
CREATE MATERIALIZED VIEW mv_resumo_canal AS
SELECT c.id_canal,
       c.nome,
       c.nro_plataforma,
       c.id_streamer,
       c.qtd_videos,
       COALESCE(p.total_usd, 0) AS patrocinio_usd,
       COALESCE(m.qtd, 0) AS qtd_membros,
       COALESCE(m.total_usd, 0) AS membros_usd_mes,
       COALESCE(i.qtd_on, 0) AS coment_online,
       COALESCE(i.qtd_off, 0) AS coment_offline,
       COALESCE(i.qtd_on, 0) + COALESCE(i.qtd_off, 0) AS interacoes,
       COALESCE(d.qtd, 0) AS qtd_doacoes,
       COALESCE(d.qtd_coment, 0) AS coment_com_doacao,
       COALESCE(d.total_usd, 0) AS doacoes_usd,
       COALESCE(p.total_usd, 0) + COALESCE(m.total_usd, 0) + COALESCE(d.total_usd, 0) AS receita_usd
FROM Canal c
LEFT JOIN (
    SELECT id_canal, SUM(valor) AS total_usd
    FROM Patrocinio
    GROUP BY id_canal
) p ON p.id_canal = c.id_canal
LEFT JOIN (
    SELECT i.id_canal, COUNT(*) AS qtd, SUM(n.valor) AS total_usd
    FROM Inscricao i
    JOIN NivelCanal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
    GROUP BY i.id_canal
) m ON m.id_canal = c.id_canal
LEFT JOIN (
    SELECT v.id_canal,
           SUM(CASE WHEN co.coment_on THEN 1 ELSE 0 END) AS qtd_on,
           SUM(CASE WHEN co.coment_on THEN 0 ELSE 1 END) AS qtd_off
    FROM Comentario co
    JOIN Video v ON v.id_video = co.id_video
    GROUP BY v.id_canal
) i ON i.id_canal = c.id_canal
LEFT JOIN (
    SELECT v.id_canal, COUNT(*) AS qtd,
           COUNT(DISTINCT (d.id_video, d.id_usuario, d.seq_comentario)) AS qtd_coment,
           SUM(d.valor * cv.fator_conver) AS total_usd
    FROM Doacao d
    JOIN Video v ON v.id_video = d.id_video
    JOIN Usuario u ON u.id_usuario = d.id_usuario
    JOIN Pais pa ON pa.DDI = u.pais_residencia
    JOIN Conversao cv ON cv.moeda = pa.moeda
    WHERE d.status IN ('recebido', 'lido')
    GROUP BY v.id_canal
) d ON d.id_canal = c.id_canal;

-- o REFRESH CONCURRENTLY exige um índice único; este também serve o filtro por canal
CREATE UNIQUE INDEX uq_mv_resumo_canal ON mv_resumo_canal USING btree (id_canal);

-- filtro por streamer é sempre igualdade, por isso hash
CREATE INDEX idx_mv_resumo_streamer ON mv_resumo_canal USING hash (id_streamer);

-- filtro por plataforma; o CLUSTER deixa os canais da mesma plataforma juntos
CREATE INDEX idx_mv_resumo_plataforma ON mv_resumo_canal USING btree (nro_plataforma);
CLUSTER mv_resumo_canal USING idx_mv_resumo_plataforma;

-- comentários online, offline e total por vídeo (consulta 2)
CREATE MATERIALIZED VIEW mv_interacoes_video AS
SELECT v.id_video,
       v.id_canal,
       c.nome AS canal,
       c.nro_plataforma,
       v.titulo,
       v.dataH,
       SUM(CASE WHEN co.coment_on THEN 1 ELSE 0 END) AS coment_online,
       SUM(CASE WHEN NOT co.coment_on THEN 1 ELSE 0 END) AS coment_offline,
       COUNT(co.seq) AS total_comentarios
FROM Video v
JOIN Canal c ON c.id_canal = v.id_canal
LEFT JOIN Comentario co ON co.id_video = v.id_video
GROUP BY v.id_video, v.id_canal, c.nome, c.nro_plataforma, v.titulo, v.dataH;

-- id_canal na frente pra servir o filtro por canal
CREATE UNIQUE INDEX uq_mv_interacoes_video ON mv_interacoes_video USING btree (id_canal, id_video);

-- já entrega os vídeos na ordem do ranking
CREATE INDEX idx_mv_interacoes_total ON mv_interacoes_video USING btree (total_comentarios DESC);
CLUSTER mv_interacoes_video USING idx_mv_interacoes_total;

-- vídeos e visualizações de cada streamer por plataforma (consultas 1 e 12)
CREATE VIEW vw_streamer_plataforma AS
SELECT id_streamer,
       nro_plataforma,
       COUNT(*) AS qtd_canais,
       SUM(qtd_videos) AS qtd_videos,
       SUM(qtd_visualizacoes) AS qtd_visualizacoes
FROM Canal
GROUP BY id_streamer, nro_plataforma;

-- patrocínios com os nomes da empresa e do canal (consulta 5)
CREATE VIEW vw_patrocinio_empresa AS
SELECT e.nro AS nro_empresa,
       e.nome AS empresa,
       e.nome_fantasia,
       c.id_canal,
       c.nome AS canal,
       c.nro_plataforma,
       p.valor AS valor_usd
FROM Patrocinio p
JOIN Empresa e ON e.nro = p.nro_empresa
JOIN Canal c ON c.id_canal = p.id_canal;

-- de quantos canais cada usuário é membro e quanto paga por mês (consulta 6)
CREATE VIEW vw_membro_usuario AS
SELECT u.id_usuario,
       u.nick,
       COUNT(*) AS qtd_canais,
       SUM(n.valor) AS total_mensal_usd
FROM Inscricao i
JOIN NivelCanal n ON n.id_canal = i.id_canal AND n.nivel = i.nivel
JOIN Usuario u ON u.id_usuario = i.id_membro
GROUP BY u.id_usuario, u.nick;

-- atualiza as duas materializadas; com TRUE refaz também o CLUSTER
CREATE OR REPLACE FUNCTION atualizar_visoes(p_reorganizar BOOLEAN DEFAULT FALSE) RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_resumo_canal;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_interacoes_video;
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
