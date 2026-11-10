\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

CREATE OR REPLACE FUNCTION id_do_canal(p_canal VARCHAR, p_plataforma INTEGER) RETURNS INTEGER AS $$
DECLARE
    v_id Canal.id_canal%TYPE;
BEGIN
    IF p_plataforma IS NULL THEN
        SELECT c.id_canal INTO STRICT v_id FROM Canal c WHERE c.nome = p_canal;
    ELSE
        SELECT c.id_canal INTO STRICT v_id
          FROM Canal c
         WHERE c.nro_plataforma = p_plataforma AND c.nome = p_canal;
    END IF;
    RETURN v_id;
EXCEPTION
    WHEN no_data_found THEN
        RAISE EXCEPTION 'Canal "%" não encontrado', p_canal;
    WHEN too_many_rows THEN
        RAISE EXCEPTION 'Canal "%" existe em mais de uma plataforma: informe também o nro da plataforma', p_canal;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION streamers_mais_videos(p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (streamer VARCHAR, qtd_videos BIGINT, visualizacoes NUMERIC) AS $$
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT u.nick, t.videos, t.visu
          FROM (SELECT s.id_streamer,
                       SUM(s.qtd_videos)::BIGINT AS videos,
                       SUM(s.qtd_visualizacoes) AS visu
                  FROM vw_streamer_plataforma s
                 GROUP BY s.id_streamer) AS t
          JOIN Usuario u ON u.id_usuario = t.id_streamer
         ORDER BY t.videos DESC, t.visu DESC;
    ELSE
        RETURN QUERY
        SELECT u.nick, s.qtd_videos, s.qtd_visualizacoes
          FROM vw_streamer_plataforma s
          JOIN Usuario u ON u.id_usuario = s.id_streamer
         WHERE s.nro_plataforma = p_plataforma
         ORDER BY s.qtd_videos DESC, s.qtd_visualizacoes DESC;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION videos_mais_comentados(p_canal VARCHAR DEFAULT NULL, p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, titulo VARCHAR, postado_em TIMESTAMP,
               coment_online BIGINT, coment_offline BIGINT, total_comentarios BIGINT) AS $$
DECLARE
    v_canal Canal.id_canal%TYPE;
BEGIN
    IF p_canal IS NULL THEN
        RETURN QUERY
        SELECT i.canal, i.nro_plataforma, i.titulo, i.dataH,
               i.coment_online, i.coment_offline, i.total_comentarios
          FROM mv_interacoes_video i
         ORDER BY i.total_comentarios DESC;
    ELSE
        v_canal := id_do_canal(p_canal, p_plataforma);
        RETURN QUERY
        SELECT i.canal, i.nro_plataforma, i.titulo, i.dataH,
               i.coment_online, i.coment_offline, i.total_comentarios
          FROM mv_interacoes_video i
         WHERE i.id_canal = v_canal
         ORDER BY i.total_comentarios DESC;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION canais_por_interacoes(p_streamer VARCHAR DEFAULT NULL)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, interacoes BIGINT,
               qtd_videos INTEGER, media_por_video NUMERIC) AS $$
BEGIN
    IF p_streamer IS NULL THEN
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, m.interacoes, m.qtd_videos,
               COALESCE(round(m.interacoes::NUMERIC / NULLIF(m.qtd_videos, 0), 2), 0)
          FROM mv_resumo_canal m
         ORDER BY m.interacoes DESC;
    ELSE
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, m.interacoes, m.qtd_videos,
               COALESCE(round(m.interacoes::NUMERIC / NULLIF(m.qtd_videos, 0), 2), 0)
          FROM mv_resumo_canal m
         WHERE m.id_streamer = (SELECT u.id_usuario FROM Usuario u WHERE u.nick = p_streamer)
         ORDER BY m.interacoes DESC;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION canais_por_media_doacao(p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, media_por_comentario NUMERIC,
               qtd_doacoes BIGINT, total_usd NUMERIC) AS $$
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, round(m.doacoes_usd / m.coment_com_doacao, 2),
               m.qtd_doacoes, round(m.doacoes_usd, 2)
          FROM mv_resumo_canal m
         WHERE m.qtd_doacoes > 0
         ORDER BY 3 DESC;
    ELSE
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, round(m.doacoes_usd / m.coment_com_doacao, 2),
               m.qtd_doacoes, round(m.doacoes_usd, 2)
          FROM mv_resumo_canal m
         WHERE m.nro_plataforma = p_plataforma AND m.qtd_doacoes > 0
         ORDER BY 3 DESC;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION patrocinios_por_empresa(p_empresa INTEGER DEFAULT NULL)
RETURNS TABLE (nro_empresa INTEGER, empresa VARCHAR, canal VARCHAR,
               nro_plataforma INTEGER, valor_usd NUMERIC) AS $$
BEGIN
    IF p_empresa IS NULL THEN
        RETURN QUERY
        SELECT v.nro_empresa, v.empresa, v.canal, v.nro_plataforma, v.valor_usd
          FROM vw_patrocinio_empresa v
         ORDER BY v.nro_empresa, v.valor_usd DESC;
    ELSE
        RETURN QUERY
        SELECT v.nro_empresa, v.empresa, v.canal, v.nro_plataforma, v.valor_usd
          FROM vw_patrocinio_empresa v
         WHERE v.nro_empresa = p_empresa
         ORDER BY v.valor_usd DESC;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gasto_dos_membros(p_usuario VARCHAR DEFAULT NULL)
RETURNS TABLE (usuario VARCHAR, qtd_canais BIGINT, total_mensal_usd NUMERIC) AS $$
BEGIN
    IF p_usuario IS NULL THEN
        RETURN QUERY
        SELECT v.nick, v.qtd_canais, v.total_mensal_usd
          FROM vw_membro_usuario v
         ORDER BY v.total_mensal_usd DESC;
    ELSE
        RETURN QUERY
        SELECT v.nick, v.qtd_canais, v.total_mensal_usd
          FROM vw_membro_usuario v
         WHERE v.nick = p_usuario;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION canais_com_doacao(p_canal VARCHAR DEFAULT NULL, p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, total_usd NUMERIC) AS $$
DECLARE
    v_canal Canal.id_canal%TYPE;
BEGIN
    IF p_canal IS NULL THEN
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, round(m.doacoes_usd, 2)
          FROM mv_resumo_canal m
         WHERE m.qtd_doacoes > 0
         ORDER BY m.doacoes_usd DESC;
    ELSE
        v_canal := id_do_canal(p_canal, p_plataforma);
        RETURN QUERY
        SELECT m.nome, m.nro_plataforma, round(m.doacoes_usd, 2)
          FROM mv_resumo_canal m
         WHERE m.id_canal = v_canal AND m.qtd_doacoes > 0;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_canais_patrocinio(p_k INTEGER)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, patrocinio_usd NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT m.nome, m.nro_plataforma, m.patrocinio_usd
      FROM mv_resumo_canal m
     WHERE m.patrocinio_usd > 0
     ORDER BY m.patrocinio_usd DESC
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_canais_membros(p_k INTEGER)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_membros BIGINT, membros_usd_mes NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT m.nome, m.nro_plataforma, m.qtd_membros, m.membros_usd_mes
      FROM mv_resumo_canal m
     WHERE m.membros_usd_mes > 0
     ORDER BY m.membros_usd_mes DESC
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_canais_doacoes(p_k INTEGER)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_doacoes BIGINT, doacoes_usd NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT m.nome, m.nro_plataforma, m.qtd_doacoes, round(m.doacoes_usd, 2)
      FROM mv_resumo_canal m
     WHERE m.doacoes_usd > 0
     ORDER BY m.doacoes_usd DESC
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_canais_faturamento(p_k INTEGER)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, patrocinio_usd NUMERIC,
               membros_usd_mes NUMERIC, doacoes_usd NUMERIC, receita_usd NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT m.nome, m.nro_plataforma, m.patrocinio_usd, m.membros_usd_mes,
           round(m.doacoes_usd, 2), round(m.receita_usd, 2)
      FROM mv_resumo_canal m
     ORDER BY m.receita_usd DESC
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION top_plataformas(p_k INTEGER, p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (plataforma VARCHAR, qtd_streamers BIGINT, qtd_canais BIGINT) AS $$
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT pl.nome, t.streamers, t.canais
          FROM (SELECT s.nro_plataforma,
                       COUNT(*) AS streamers,
                       SUM(s.qtd_canais)::BIGINT AS canais
                  FROM vw_streamer_plataforma s
                 GROUP BY s.nro_plataforma
                 ORDER BY 2 DESC, 3 DESC
                 LIMIT p_k) AS t
          JOIN Plataforma pl ON pl.nro = t.nro_plataforma
         ORDER BY t.streamers DESC, t.canais DESC;
    ELSE
        RETURN QUERY
        SELECT pl.nome, COUNT(*), SUM(s.qtd_canais)::BIGINT
          FROM vw_streamer_plataforma s
          JOIN Plataforma pl ON pl.nro = s.nro_plataforma
         WHERE s.nro_plataforma = p_plataforma
         GROUP BY pl.nome;
    END IF;
END;
$$ LANGUAGE plpgsql;
