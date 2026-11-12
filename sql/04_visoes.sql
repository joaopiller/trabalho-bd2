\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP VIEW IF EXISTS vw_streamer_plataforma, vw_patrocinio_empresa, vw_membro_usuario;
DROP MATERIALIZED VIEW IF EXISTS mv_interacoes_video;
DROP MATERIALIZED VIEW IF EXISTS mv_resumo_canal;

-- resumo por canal com o que é caro de calcular na hora (consultas 1, 3, 4 e 7 a 12)
CREATE MATERIALIZED VIEW mv_resumo_canal AS
SELECT c.id_canal,
       c.nro_plataforma,
       c.id_streamer,
       c.qtd_videos,
       c.qtd_visualizacoes,
       COALESCE(i.qtd, 0) AS interacoes,
       COALESCE(m.qtd, 0)::INTEGER AS qtd_membros,
       COALESCE(d.qtd, 0)::INTEGER AS qtd_doacoes,
       COALESCE(d.qtd_coment, 0)::INTEGER AS coment_com_doacao,
       s.nick AS streamer,
       c.nome,
       COALESCE(p.total_usd, 0) AS patrocinio_usd,
       COALESCE(m.total_usd, 0) AS membros_usd_mes,
       COALESCE(d.total_usd, 0) AS doacoes_usd
FROM Canal c
JOIN Usuario s ON s.id_usuario = c.id_streamer
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
    SELECT v.id_canal, COUNT(*) AS qtd
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

-- único por causa do REFRESH CONCURRENTLY; a plataforma na frente atende o filtro por plataforma
CREATE UNIQUE INDEX uq_mv_resumo_canal ON mv_resumo_canal USING btree (nro_plataforma, id_canal);
-- deixa os canais da mesma plataforma juntos no disco
CLUSTER mv_resumo_canal USING uq_mv_resumo_canal;

-- filtro por streamer é sempre igualdade, por isso hash
CREATE INDEX idx_mv_resumo_streamer ON mv_resumo_canal USING hash (id_streamer);

-- já entrega os canais na ordem do que recebem de membros (consulta 9)
CREATE INDEX idx_mv_resumo_membros ON mv_resumo_canal USING btree (membros_usd_mes DESC, id_canal);

-- a receita é a soma das três fontes, indexada sem precisar guardar a coluna (consulta 11)
CREATE INDEX idx_mv_resumo_receita ON mv_resumo_canal USING btree ((patrocinio_usd + membros_usd_mes + doacoes_usd) DESC, id_canal);

-- comentários online e offline por vídeo; o total é a soma dos dois (consulta 2)
CREATE MATERIALIZED VIEW mv_interacoes_video AS
SELECT v.id_video,
       v.id_canal,
       c.nro_plataforma,
       COALESCE(SUM(CASE WHEN co.coment_on THEN 1 ELSE 0 END), 0)::INTEGER AS coment_online,
       COALESCE(SUM(CASE WHEN NOT co.coment_on THEN 1 ELSE 0 END), 0)::INTEGER AS coment_offline,
       v.dataH,
       c.nome AS canal,
       v.titulo
FROM Video v
JOIN Canal c ON c.id_canal = v.id_canal
LEFT JOIN Comentario co ON co.id_video = v.id_video
GROUP BY v.id_video, v.id_canal, c.nome, c.nro_plataforma, v.titulo, v.dataH;

-- único por causa do REFRESH CONCURRENTLY; o canal na frente atende o filtro por canal
CREATE UNIQUE INDEX uq_mv_interacoes_video ON mv_interacoes_video USING btree (id_canal, id_video);
-- deixa os vídeos do mesmo canal juntos no disco
CLUSTER mv_interacoes_video USING uq_mv_interacoes_video;

-- vídeos e visualizações de cada streamer por plataforma, a partir do resumo por canal (consultas 1 e 12)
CREATE VIEW vw_streamer_plataforma AS
SELECT id_streamer,
       streamer,
       nro_plataforma,
       COUNT(*) AS qtd_canais,
       SUM(qtd_videos) AS qtd_videos,
       SUM(qtd_visualizacoes) AS qtd_visualizacoes
FROM mv_resumo_canal
GROUP BY id_streamer, streamer, nro_plataforma;

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
