\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP TRIGGER IF EXISTS comentario_bi ON Comentario;
DROP TRIGGER IF EXISTS comentario_bu ON Comentario;
DROP TRIGGER IF EXISTS doacao_seq_bi ON Doacao;
DROP TRIGGER IF EXISTS doacao_total_ai ON Doacao;
DROP TRIGGER IF EXISTS mecplat_seq_bi ON MecanismoPlat;
DROP TRIGGER IF EXISTS video_qtd_ai ON Video;
DROP TRIGGER IF EXISTS video_qtd_ad ON Video;
DROP TRIGGER IF EXISTS video_qtd_au ON Video;
DROP TRIGGER IF EXISTS bitcoin_subtipo_bi ON BitCoin;
DROP TRIGGER IF EXISTS paypal_subtipo_bi ON PayPal;
DROP TRIGGER IF EXISTS cartaocredito_subtipo_bi ON CartaoCredito;
DROP TRIGGER IF EXISTS mecanismoplat_subtipo_bi ON MecanismoPlat;

-- Comentario.seq: sequencial por (vídeo, usuário)
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
        -- trava a linha do usuário: dois comentários simultâneos dele não leem o mesmo MAX
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

-- Doacao.seq_pg: sequencial por comentário
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

-- MecanismoPlat.seq_plataforma: sequencial entre as doações do mesmo comentário feitas pela plataforma
-- (usuário e plataforma já são determinados pelo comentário)
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

-- Canal.qtd_videos acompanha INSERT, DELETE e troca de canal do vídeo
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

-- especialização disjunta: a doação só pode estar em uma das quatro tabelas
CREATE OR REPLACE FUNCTION trg_doacao_subtipo() RETURNS trigger AS $$
BEGIN
    -- trava a doação para duas transações não gravarem formas diferentes ao mesmo tempo
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

-- especialização total: conferida no COMMIT, porque a forma de pagamento é inserida depois da doação
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
