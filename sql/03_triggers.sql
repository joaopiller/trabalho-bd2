\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP TRIGGER IF EXISTS comentario_bi ON Comentario;
DROP TRIGGER IF EXISTS comentario_bu ON Comentario;
DROP TRIGGER IF EXISTS doacao_seq_bi ON Doacao;
DROP TRIGGER IF EXISTS doacao_total_ai ON Doacao;
DROP TRIGGER IF EXISTS mecplat_seq_bi ON MecanismoPlat;
DROP TRIGGER IF EXISTS video_data_bi ON Video;
DROP TRIGGER IF EXISTS video_qtd_ai ON Video;
DROP TRIGGER IF EXISTS video_qtd_ad ON Video;
DROP TRIGGER IF EXISTS video_qtd_au ON Video;
DROP TRIGGER IF EXISTS bitcoin_subtipo_bi ON BitCoin;
DROP TRIGGER IF EXISTS paypal_subtipo_bi ON PayPal;
DROP TRIGGER IF EXISTS cartaocredito_subtipo_bi ON CartaoCredito;
DROP TRIGGER IF EXISTS mecanismoplat_subtipo_bi ON MecanismoPlat;
DROP TRIGGER IF EXISTS participa_dono_bi ON Participa;

CREATE OR REPLACE FUNCTION trg_comentario_insere() RETURNS trigger AS $$
DECLARE
    v_data_video Video.dataH%TYPE;
BEGIN
    SELECT dataH INTO v_data_video FROM Video WHERE id_video = NEW.id_video;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vídeo % não existe', NEW.id_video;
    END IF;
    IF NEW.dataH < v_data_video THEN
        RAISE EXCEPTION 'Comentário (%) anterior ao vídeo % (%)', NEW.dataH, NEW.id_video, v_data_video;
    END IF;
    IF NEW.seq IS NULL THEN
        PERFORM 1 FROM Usuario WHERE id_usuario = NEW.id_usuario FOR NO KEY UPDATE;
        SELECT COALESCE(MAX(seq), 0) + 1 INTO NEW.seq
          FROM Comentario
         WHERE id_video = NEW.id_video AND id_usuario = NEW.id_usuario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comentario_bi
BEFORE INSERT ON Comentario
FOR EACH ROW EXECUTE PROCEDURE trg_comentario_insere();

CREATE OR REPLACE FUNCTION trg_comentario_atualiza() RETURNS trigger AS $$
DECLARE
    v_data_video Video.dataH%TYPE;
BEGIN
    SELECT dataH INTO v_data_video FROM Video WHERE id_video = NEW.id_video;
    IF NEW.dataH < v_data_video THEN
        RAISE EXCEPTION 'Comentário (%) anterior ao vídeo % (%)', NEW.dataH, NEW.id_video, v_data_video;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comentario_bu
BEFORE UPDATE OF dataH, id_video ON Comentario
FOR EACH ROW EXECUTE PROCEDURE trg_comentario_atualiza();

CREATE OR REPLACE FUNCTION trg_doacao_seq() RETURNS trigger AS $$
BEGIN
    IF NEW.seq_pg IS NULL THEN
        PERFORM 1 FROM Comentario
         WHERE id_video = NEW.id_video AND id_usuario = NEW.id_usuario AND seq = NEW.seq_comentario
           FOR NO KEY UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Comentário (%, %, %) não existe', NEW.id_video, NEW.id_usuario, NEW.seq_comentario;
        END IF;
        SELECT COALESCE(MAX(seq_pg), 0) + 1 INTO NEW.seq_pg
          FROM Doacao
         WHERE id_video = NEW.id_video AND id_usuario = NEW.id_usuario AND seq_comentario = NEW.seq_comentario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER doacao_seq_bi
BEFORE INSERT ON Doacao
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_seq();

CREATE OR REPLACE FUNCTION trg_mecplat_seq() RETURNS trigger AS $$
DECLARE
    v_doacao Doacao%ROWTYPE;
BEGIN
    IF NEW.seq_plataforma IS NULL THEN
        SELECT * INTO v_doacao FROM Doacao WHERE id_doacao = NEW.id_doacao;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Doação % não existe', NEW.id_doacao;
        END IF;
        PERFORM 1 FROM Comentario
         WHERE id_video = v_doacao.id_video AND id_usuario = v_doacao.id_usuario AND seq = v_doacao.seq_comentario
           FOR NO KEY UPDATE;
        SELECT COALESCE(MAX(m.seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
          FROM Doacao d
          JOIN MecanismoPlat m ON m.id_doacao = d.id_doacao
         WHERE d.id_video = v_doacao.id_video AND d.id_usuario = v_doacao.id_usuario
           AND d.seq_comentario = v_doacao.seq_comentario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER mecplat_seq_bi
BEFORE INSERT ON MecanismoPlat
FOR EACH ROW EXECUTE PROCEDURE trg_mecplat_seq();

CREATE OR REPLACE FUNCTION trg_video_data() RETURNS trigger AS $$
DECLARE
    v_inicio Canal.data_inicio%TYPE;
BEGIN
    SELECT data_inicio INTO v_inicio FROM Canal WHERE id_canal = NEW.id_canal;
    IF NEW.dataH < v_inicio THEN
        RAISE EXCEPTION 'Vídeo (%) anterior ao início do canal % (%)', NEW.dataH, NEW.id_canal, v_inicio;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_data_bi
BEFORE INSERT OR UPDATE OF dataH, id_canal ON Video
FOR EACH ROW EXECUTE PROCEDURE trg_video_data();

CREATE OR REPLACE FUNCTION trg_video_insere() RETURNS trigger AS $$
BEGIN
    UPDATE Canal SET qtd_videos = qtd_videos + 1 WHERE id_canal = NEW.id_canal;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_video_remove() RETURNS trigger AS $$
BEGIN
    UPDATE Canal SET qtd_videos = qtd_videos - 1 WHERE id_canal = OLD.id_canal;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_video_muda_canal() RETURNS trigger AS $$
BEGIN
    IF NEW.id_canal <> OLD.id_canal THEN
        UPDATE Canal SET qtd_videos = qtd_videos - 1 WHERE id_canal = OLD.id_canal;
        UPDATE Canal SET qtd_videos = qtd_videos + 1 WHERE id_canal = NEW.id_canal;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_qtd_ai AFTER INSERT ON Video
FOR EACH ROW EXECUTE PROCEDURE trg_video_insere();

CREATE TRIGGER video_qtd_ad AFTER DELETE ON Video
FOR EACH ROW EXECUTE PROCEDURE trg_video_remove();

CREATE TRIGGER video_qtd_au AFTER UPDATE OF id_canal ON Video
FOR EACH ROW EXECUTE PROCEDURE trg_video_muda_canal();

CREATE OR REPLACE FUNCTION trg_doacao_subtipo() RETURNS trigger AS $$
BEGIN
    PERFORM 1 FROM Doacao WHERE id_doacao = NEW.id_doacao FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Doação % não existe', NEW.id_doacao;
    END IF;
    IF EXISTS (SELECT 1 FROM BitCoin WHERE id_doacao = NEW.id_doacao)
       OR EXISTS (SELECT 1 FROM PayPal WHERE id_doacao = NEW.id_doacao)
       OR EXISTS (SELECT 1 FROM CartaoCredito WHERE id_doacao = NEW.id_doacao)
       OR EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_doacao = NEW.id_doacao) THEN
        RAISE EXCEPTION 'Doação % já tem forma de pagamento', NEW.id_doacao;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER bitcoin_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON BitCoin
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_subtipo();

CREATE TRIGGER paypal_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON PayPal
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_subtipo();

CREATE TRIGGER cartaocredito_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON CartaoCredito
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_subtipo();

CREATE TRIGGER mecanismoplat_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON MecanismoPlat
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_subtipo();

CREATE OR REPLACE FUNCTION trg_doacao_total() RETURNS trigger AS $$
BEGIN
    IF NOT (EXISTS (SELECT 1 FROM BitCoin WHERE id_doacao = NEW.id_doacao)
            OR EXISTS (SELECT 1 FROM PayPal WHERE id_doacao = NEW.id_doacao)
            OR EXISTS (SELECT 1 FROM CartaoCredito WHERE id_doacao = NEW.id_doacao)
            OR EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_doacao = NEW.id_doacao)) THEN
        RAISE EXCEPTION 'Doação % sem forma de pagamento', NEW.id_doacao;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER doacao_total_ai
AFTER INSERT ON Doacao
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE trg_doacao_total();

CREATE OR REPLACE FUNCTION trg_participa_dono() RETURNS trigger AS $$
DECLARE
    v_dono Canal.id_streamer%TYPE;
BEGIN
    SELECT c.id_streamer INTO v_dono
      FROM Video v JOIN Canal c ON c.id_canal = v.id_canal
     WHERE v.id_video = NEW.id_video;
    IF v_dono = NEW.id_streamer THEN
        RAISE EXCEPTION 'Streamer % é dono do canal do vídeo %', NEW.id_streamer, NEW.id_video;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER participa_dono_bi
BEFORE INSERT OR UPDATE ON Participa
FOR EACH ROW EXECUTE PROCEDURE trg_participa_dono();

CREATE OR REPLACE FUNCTION recalcular_derivados() RETURNS void AS $$
BEGIN
    UPDATE Canal c
       SET qtd_visualizacoes = s.vis, qtd_videos = s.vid
      FROM (SELECT ca.id_canal, COALESCE(SUM(v.visu_total), 0) AS vis, COUNT(v.id_video) AS vid
              FROM Canal ca LEFT JOIN Video v ON v.id_canal = ca.id_canal
             GROUP BY ca.id_canal) AS s
     WHERE s.id_canal = c.id_canal
       AND (c.qtd_visualizacoes <> s.vis OR c.qtd_videos <> s.vid);

    UPDATE Plataforma p
       SET qtd_users = s.n
      FROM (SELECT pl.nro, COUNT(pu.id_usuario) AS n
              FROM Plataforma pl LEFT JOIN PlataformaUsuario pu ON pu.nro_plataforma = pl.nro
             GROUP BY pl.nro) AS s
     WHERE s.nro = p.nro
       AND p.qtd_users <> s.n;
END;
$$ LANGUAGE plpgsql;
