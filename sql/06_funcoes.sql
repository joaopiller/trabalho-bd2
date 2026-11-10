\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

-- Resolvedores: permitem filtrar pelo nome do canal e pelo nick do usuario,
-- em vez de exigir os identificadores artificiais.
CREATE OR REPLACE FUNCTION id_do_canal(p_canal VARCHAR, p_plataforma INTEGER DEFAULT NULL)
RETURNS INTEGER AS $$
DECLARE
    v_id Canal.id_canal%TYPE;
BEGIN
    IF p_plataforma IS NULL THEN
        SELECT c.id_canal INTO STRICT v_id FROM Canal c WHERE c.nome = p_canal;
    ELSE
        SELECT c.id_canal INTO STRICT v_id
          FROM Canal c WHERE c.nro_plataforma = p_plataforma AND c.nome = p_canal;
    END IF;
    RETURN v_id;
EXCEPTION
    WHEN no_data_found  THEN RAISE EXCEPTION 'Canal "%" nao encontrado', p_canal;
    WHEN too_many_rows  THEN RAISE EXCEPTION
        'Canal "%" existe em mais de uma plataforma: informe tambem o nro da plataforma', p_canal;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION id_do_usuario(p_nick VARCHAR) RETURNS INTEGER AS $$
DECLARE
    v_id Usuario.id_usuario%TYPE;
BEGIN
    SELECT u.id_usuario INTO STRICT v_id FROM Usuario u WHERE u.nick = p_nick;
    RETURN v_id;
EXCEPTION
    WHEN no_data_found THEN RAISE EXCEPTION 'Usuario "%" nao encontrado', p_nick;
END;
$$ LANGUAGE plpgsql STABLE;

-- Consulta 1
CREATE OR REPLACE FUNCTION streamers_mais_videos(p_plataforma INTEGER DEFAULT NULL,
                                                 p_k INTEGER DEFAULT 10)
RETURNS TABLE (streamer VARCHAR, qtd_canais BIGINT, qtd_videos BIGINT, visualizacoes NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT u.nick, t.canais, t.videos, t.visu
          FROM (SELECT s.id_streamer,
                       SUM(s.qtd_canais)::BIGINT        AS canais,
                       SUM(s.qtd_videos)::BIGINT        AS videos,
                       SUM(s.qtd_visualizacoes)::NUMERIC AS visu
                  FROM vw_streamer_plataforma s
                 GROUP BY s.id_streamer) AS t
          JOIN Usuario u ON u.id_usuario = t.id_streamer
         WHERE t.videos > 0
         ORDER BY t.videos DESC, t.visu DESC, u.nick
         LIMIT p_k;
    ELSE
        RETURN QUERY
        SELECT u.nick, s.qtd_canais, s.qtd_videos::BIGINT, s.qtd_visualizacoes::NUMERIC
          FROM vw_streamer_plataforma s
          JOIN Usuario u ON u.id_usuario = s.id_streamer
         WHERE s.nro_plataforma = p_plataforma AND s.qtd_videos > 0
         ORDER BY s.qtd_videos DESC, s.qtd_visualizacoes DESC, u.nick
         LIMIT p_k;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 2
CREATE OR REPLACE FUNCTION videos_mais_comentados(p_canal VARCHAR DEFAULT NULL,
                                                  p_plataforma INTEGER DEFAULT NULL,
                                                  p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, titulo VARCHAR, postado_em TIMESTAMP,
               coment_online BIGINT, coment_offline BIGINT, total_comentarios BIGINT) AS $$
#variable_conflict use_column
DECLARE
    v_canal INTEGER;
BEGIN
    IF p_canal IS NULL THEN
        RETURN QUERY
        SELECT i.canal, i.nro_plataforma, i.titulo, i.dataH,
               i.coment_online, i.coment_offline, i.total_comentarios
          FROM mv_interacoes_video i
         WHERE i.total_comentarios > 0
         ORDER BY i.total_comentarios DESC, i.id_video
         LIMIT p_k;
    ELSE
        v_canal := id_do_canal(p_canal, p_plataforma);
        RETURN QUERY
        SELECT i.canal, i.nro_plataforma, i.titulo, i.dataH,
               i.coment_online, i.coment_offline, i.total_comentarios
          FROM mv_interacoes_video i
         WHERE i.id_canal = v_canal AND i.total_comentarios > 0
         ORDER BY i.total_comentarios DESC, i.id_video
         LIMIT p_k;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 3
CREATE OR REPLACE FUNCTION canais_por_interacoes(p_streamer VARCHAR DEFAULT NULL,
                                                 p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, coment_online BIGINT, coment_offline BIGINT,
               interacoes BIGINT, media_por_video NUMERIC) AS $$
#variable_conflict use_column
DECLARE
    v_streamer INTEGER;
BEGIN
    IF p_streamer IS NULL THEN
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.coment_online, r.coment_offline, r.interacoes,
               CASE WHEN r.qtd_videos = 0 THEN 0::NUMERIC
                    ELSE ROUND(r.interacoes::NUMERIC / r.qtd_videos, 2) END
          FROM mv_resumo_canal r
         ORDER BY r.interacoes DESC, r.id_canal
         LIMIT p_k;
    ELSE
        v_streamer := id_do_usuario(p_streamer);
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.coment_online, r.coment_offline, r.interacoes,
               CASE WHEN r.qtd_videos = 0 THEN 0::NUMERIC
                    ELSE ROUND(r.interacoes::NUMERIC / r.qtd_videos, 2) END
          FROM mv_resumo_canal r
         WHERE r.id_streamer = v_streamer
         ORDER BY r.interacoes DESC, r.id_canal
         LIMIT p_k;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 4
CREATE OR REPLACE FUNCTION canais_por_media_doacao(p_plataforma INTEGER DEFAULT NULL,
                                                   p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_doacoes BIGINT,
               total_usd NUMERIC, media_por_comentario_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.qtd_doacoes, r.doacoes_usd,
               ROUND(r.doacoes_usd / r.coment_com_doacao, 2)
          FROM mv_resumo_canal r
         WHERE r.coment_com_doacao > 0
         ORDER BY 5 DESC, r.id_canal
         LIMIT p_k;
    ELSE
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.qtd_doacoes, r.doacoes_usd,
               ROUND(r.doacoes_usd / r.coment_com_doacao, 2)
          FROM mv_resumo_canal r
         WHERE r.nro_plataforma = p_plataforma AND r.coment_com_doacao > 0
         ORDER BY 5 DESC, r.id_canal
         LIMIT p_k;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 5
CREATE OR REPLACE FUNCTION patrocinios_por_empresa(p_empresa INTEGER DEFAULT NULL)
RETURNS TABLE (nro_empresa INTEGER, empresa VARCHAR, canal VARCHAR,
               nro_plataforma INTEGER, valor_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    IF p_empresa IS NULL THEN
        RETURN QUERY
        SELECT v.nro_empresa, v.empresa, v.canal, v.nro_plataforma, v.valor_usd
          FROM vw_patrocinio_empresa v
         ORDER BY v.nro_empresa, v.valor_usd DESC, v.id_canal;
    ELSE
        RETURN QUERY
        SELECT v.nro_empresa, v.empresa, v.canal, v.nro_plataforma, v.valor_usd
          FROM vw_patrocinio_empresa v
         WHERE v.nro_empresa = p_empresa
         ORDER BY v.valor_usd DESC, v.id_canal;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 6
CREATE OR REPLACE FUNCTION gasto_dos_membros(p_usuario VARCHAR DEFAULT NULL)
RETURNS TABLE (membro VARCHAR, qtd_canais BIGINT, total_mensal_usd NUMERIC) AS $$
#variable_conflict use_column
DECLARE
    v_usuario INTEGER;
BEGIN
    IF p_usuario IS NULL THEN
        RETURN QUERY
        SELECT v.nick, v.qtd_canais, v.total_mensal_usd
          FROM vw_membro_usuario v
         ORDER BY v.total_mensal_usd DESC, v.nick;
    ELSE
        v_usuario := id_do_usuario(p_usuario);
        RETURN QUERY
        SELECT v.nick, v.qtd_canais, v.total_mensal_usd
          FROM vw_membro_usuario v
         WHERE v.id_usuario = v_usuario;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 7
CREATE OR REPLACE FUNCTION canais_com_doacao(p_canal VARCHAR DEFAULT NULL,
                                             p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_doacoes BIGINT, total_usd NUMERIC) AS $$
#variable_conflict use_column
DECLARE
    v_canal INTEGER;
BEGIN
    IF p_canal IS NULL THEN
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.qtd_doacoes, r.doacoes_usd
          FROM mv_resumo_canal r
         WHERE r.qtd_doacoes > 0
         ORDER BY r.doacoes_usd DESC, r.id_canal;
    ELSE
        v_canal := id_do_canal(p_canal, p_plataforma);
        RETURN QUERY
        SELECT r.nome, r.nro_plataforma, r.qtd_doacoes, r.doacoes_usd
          FROM mv_resumo_canal r
         WHERE r.id_canal = v_canal AND r.qtd_doacoes > 0;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta 8
CREATE OR REPLACE FUNCTION top_canais_patrocinio(p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_patrocinadores BIGINT,
               patrocinio_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT r.nome, r.nro_plataforma, r.qtd_patrocinadores, r.patrocinio_usd
      FROM mv_resumo_canal r
     WHERE r.patrocinio_usd > 0
     ORDER BY r.patrocinio_usd DESC, r.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

-- Consulta 9
CREATE OR REPLACE FUNCTION top_canais_membros(p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_membros BIGINT,
               membros_usd_mes NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT r.nome, r.nro_plataforma, r.qtd_membros, r.membros_usd_mes
      FROM mv_resumo_canal r
     WHERE r.membros_usd_mes > 0
     ORDER BY r.membros_usd_mes DESC, r.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

-- Consulta 10
CREATE OR REPLACE FUNCTION top_canais_doacoes(p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, qtd_doacoes BIGINT,
               doacoes_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT r.nome, r.nro_plataforma, r.qtd_doacoes, r.doacoes_usd
      FROM mv_resumo_canal r
     WHERE r.doacoes_usd > 0
     ORDER BY r.doacoes_usd DESC, r.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

-- Consulta 11
CREATE OR REPLACE FUNCTION top_canais_faturamento(p_k INTEGER DEFAULT 10)
RETURNS TABLE (canal VARCHAR, nro_plataforma INTEGER, patrocinio_usd NUMERIC,
               membros_usd_mes NUMERIC, doacoes_usd NUMERIC, receita_usd NUMERIC) AS $$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    SELECT r.nome, r.nro_plataforma, r.patrocinio_usd, r.membros_usd_mes,
           r.doacoes_usd, r.receita_usd
      FROM mv_resumo_canal r
     WHERE r.receita_usd > 0
     ORDER BY r.receita_usd DESC, r.id_canal
     LIMIT p_k;
END;
$$ LANGUAGE plpgsql;

-- Consulta 12 (desafio)
CREATE OR REPLACE FUNCTION top_plataformas(p_k INTEGER DEFAULT 10,
                                           p_plataforma INTEGER DEFAULT NULL)
RETURNS TABLE (nro_plataforma INTEGER, plataforma VARCHAR, qtd_streamers BIGINT,
               qtd_canais BIGINT, streamers_mais_canais BIGINT) AS $$
#variable_conflict use_column
BEGIN
    IF p_plataforma IS NULL THEN
        RETURN QUERY
        SELECT p.nro, p.nome,
               COUNT(DISTINCT c.id_streamer)::BIGINT,
               COUNT(c.id_canal)::BIGINT,
               (COUNT(DISTINCT c.id_streamer) + COUNT(c.id_canal))::BIGINT
          FROM Plataforma p
          LEFT JOIN Canal c ON c.nro_plataforma = p.nro
         GROUP BY p.nro, p.nome
         ORDER BY 5 DESC, 3 DESC, p.nro
         LIMIT p_k;
    ELSE
        RETURN QUERY
        SELECT p.nro, p.nome,
               COUNT(DISTINCT c.id_streamer)::BIGINT,
               COUNT(c.id_canal)::BIGINT,
               (COUNT(DISTINCT c.id_streamer) + COUNT(c.id_canal))::BIGINT
          FROM Plataforma p
          LEFT JOIN Canal c ON c.nro_plataforma = p.nro
         WHERE p.nro = p_plataforma
         GROUP BY p.nro, p.nome
         LIMIT p_k;
    END IF;
END;
$$ LANGUAGE plpgsql;
