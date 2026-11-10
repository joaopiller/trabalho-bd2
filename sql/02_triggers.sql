\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

-- T1: sequencial do comentario, dependente do video
CREATE OR REPLACE FUNCTION trg_comentario_bi() RETURNS trigger AS $$
DECLARE
    v_data_video Video.dataH%TYPE;
BEGIN
    SELECT v.dataH INTO v_data_video FROM Video v WHERE v.id_video = NEW.id_video FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Video % nao existe', NEW.id_video;
    END IF;

    IF NEW.dataH < v_data_video THEN
        RAISE EXCEPTION 'Comentario (%) anterior a postagem do video % (%)',
            NEW.dataH, NEW.id_video, v_data_video;
    END IF;

    IF NEW.seq IS NULL THEN
        SELECT COALESCE(MAX(c.seq), 0) + 1 INTO NEW.seq
          FROM Comentario c WHERE c.id_video = NEW.id_video;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comentario_bi BEFORE INSERT ON Comentario
FOR EACH ROW EXECUTE FUNCTION trg_comentario_bi();

CREATE OR REPLACE FUNCTION trg_comentario_bu() RETURNS trigger AS $$
DECLARE
    v_data_video Video.dataH%TYPE;
BEGIN
    SELECT v.dataH INTO v_data_video FROM Video v WHERE v.id_video = NEW.id_video;
    IF NEW.dataH < v_data_video THEN
        RAISE EXCEPTION 'Comentario (%) anterior a postagem do video % (%)',
            NEW.dataH, NEW.id_video, v_data_video;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER comentario_bu BEFORE UPDATE OF dataH, id_video ON Comentario
FOR EACH ROW EXECUTE FUNCTION trg_comentario_bu();

-- T2: video nao pode ser anterior a criacao do canal
CREATE OR REPLACE FUNCTION trg_video_data() RETURNS trigger AS $$
DECLARE
    v_inicio Canal.data_inicio%TYPE;
BEGIN
    SELECT c.data_inicio INTO v_inicio FROM Canal c WHERE c.id_canal = NEW.id_canal;
    IF NEW.dataH < v_inicio::TIMESTAMP THEN
        RAISE EXCEPTION 'Video (%) anterior ao inicio do canal % (%)',
            NEW.dataH, NEW.id_canal, v_inicio;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_data_bi BEFORE INSERT OR UPDATE OF dataH, id_canal ON Video
FOR EACH ROW EXECUTE FUNCTION trg_video_data();

-- T3: sequencial da doacao, dependente do video e do comentario
CREATE OR REPLACE FUNCTION trg_doacao_seq() RETURNS trigger AS $$
BEGIN
    IF NEW.seq_doacao IS NULL THEN
        PERFORM 1 FROM Comentario c
         WHERE c.id_video = NEW.id_video AND c.seq = NEW.seq_comentario
           FOR NO KEY UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Comentario (%, %) nao existe', NEW.id_video, NEW.seq_comentario;
        END IF;

        SELECT COALESCE(MAX(d.seq_doacao), 0) + 1 INTO NEW.seq_doacao
          FROM Doacao d
         WHERE d.id_video = NEW.id_video AND d.seq_comentario = NEW.seq_comentario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER doacao_seq_bi BEFORE INSERT ON Doacao
FOR EACH ROW EXECUTE FUNCTION trg_doacao_seq();

-- T4: sequencial do mecanismo proprio da plataforma, no escopo do comentario
-- (o comentario determina tanto o usuario quanto a plataforma citados no enunciado)
CREATE OR REPLACE FUNCTION trg_mecplat_seq() RETURNS trigger AS $$
DECLARE
    v_doacao Doacao%ROWTYPE;
BEGIN
    IF NEW.seq_plataforma IS NULL THEN
        SELECT * INTO v_doacao FROM Doacao d WHERE d.id_doacao = NEW.id_doacao;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Doacao % nao existe', NEW.id_doacao;
        END IF;

        SELECT COALESCE(MAX(m.seq_plataforma), 0) + 1 INTO NEW.seq_plataforma
          FROM MecanismoPlat m
          JOIN Doacao d ON d.id_doacao = m.id_doacao
         WHERE d.id_video = v_doacao.id_video
           AND d.seq_comentario = v_doacao.seq_comentario;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER mecplat_seq_bi BEFORE INSERT ON MecanismoPlat
FOR EACH ROW EXECUTE FUNCTION trg_mecplat_seq();

-- T5: especializacao disjunta das formas de pagamento
CREATE OR REPLACE FUNCTION trg_doacao_subtipo() RETURNS trigger AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM BitCoin       WHERE id_doacao = NEW.id_doacao)
    OR EXISTS (SELECT 1 FROM PayPal        WHERE id_doacao = NEW.id_doacao)
    OR EXISTS (SELECT 1 FROM CartaoCredito WHERE id_doacao = NEW.id_doacao)
    OR EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_doacao = NEW.id_doacao) THEN
        RAISE EXCEPTION 'Doacao % ja possui forma de pagamento', NEW.id_doacao;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER bitcoin_subtipo_bi       BEFORE INSERT OR UPDATE OF id_doacao ON BitCoin
FOR EACH ROW EXECUTE FUNCTION trg_doacao_subtipo();
CREATE TRIGGER paypal_subtipo_bi        BEFORE INSERT OR UPDATE OF id_doacao ON PayPal
FOR EACH ROW EXECUTE FUNCTION trg_doacao_subtipo();
CREATE TRIGGER cartaocredito_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON CartaoCredito
FOR EACH ROW EXECUTE FUNCTION trg_doacao_subtipo();
CREATE TRIGGER mecanismoplat_subtipo_bi BEFORE INSERT OR UPDATE OF id_doacao ON MecanismoPlat
FOR EACH ROW EXECUTE FUNCTION trg_doacao_subtipo();

-- T6: especializacao total, verificada no fim da transacao
CREATE OR REPLACE FUNCTION trg_doacao_total() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Doacao WHERE id_doacao = NEW.id_doacao) THEN
        RETURN NULL;
    END IF;

    IF NOT (EXISTS (SELECT 1 FROM BitCoin       WHERE id_doacao = NEW.id_doacao)
         OR EXISTS (SELECT 1 FROM PayPal        WHERE id_doacao = NEW.id_doacao)
         OR EXISTS (SELECT 1 FROM CartaoCredito WHERE id_doacao = NEW.id_doacao)
         OR EXISTS (SELECT 1 FROM MecanismoPlat WHERE id_doacao = NEW.id_doacao)) THEN
        RAISE EXCEPTION 'Doacao % sem forma de pagamento associada', NEW.id_doacao;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER doacao_total_ai AFTER INSERT ON Doacao
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_doacao_total();

-- T7: atributos derivados do canal, mantidos de forma incremental
CREATE OR REPLACE FUNCTION trg_video_ai() RETURNS trigger AS $$
BEGIN
    UPDATE Canal
       SET qtd_videos        = qtd_videos + 1,
           qtd_visualizacoes = qtd_visualizacoes + NEW.visu_total
     WHERE id_canal = NEW.id_canal;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_video_ad() RETURNS trigger AS $$
BEGIN
    UPDATE Canal
       SET qtd_videos        = qtd_videos - 1,
           qtd_visualizacoes = qtd_visualizacoes - OLD.visu_total
     WHERE id_canal = OLD.id_canal;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_video_au() RETURNS trigger AS $$
BEGIN
    IF NEW.id_canal <> OLD.id_canal THEN
        UPDATE Canal
           SET qtd_videos = qtd_videos - 1, qtd_visualizacoes = qtd_visualizacoes - OLD.visu_total
         WHERE id_canal = OLD.id_canal;
        UPDATE Canal
           SET qtd_videos = qtd_videos + 1, qtd_visualizacoes = qtd_visualizacoes + NEW.visu_total
         WHERE id_canal = NEW.id_canal;
    ELSIF NEW.visu_total <> OLD.visu_total THEN
        UPDATE Canal
           SET qtd_visualizacoes = qtd_visualizacoes + (NEW.visu_total - OLD.visu_total)
         WHERE id_canal = NEW.id_canal;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER video_qtd_ai AFTER INSERT ON Video
FOR EACH ROW EXECUTE FUNCTION trg_video_ai();
CREATE TRIGGER video_qtd_ad AFTER DELETE ON Video
FOR EACH ROW EXECUTE FUNCTION trg_video_ad();
CREATE TRIGGER video_qtd_au AFTER UPDATE OF id_canal, visu_total ON Video
FOR EACH ROW EXECUTE FUNCTION trg_video_au();

-- T8: qtd_users da plataforma, tambem incremental
CREATE OR REPLACE FUNCTION trg_platusuario() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE Plataforma SET qtd_users = qtd_users + 1 WHERE nro = NEW.nro_plataforma;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE Plataforma SET qtd_users = qtd_users - 1 WHERE nro = OLD.nro_plataforma;
    ELSIF NEW.nro_plataforma <> OLD.nro_plataforma THEN
        UPDATE Plataforma SET qtd_users = qtd_users - 1 WHERE nro = OLD.nro_plataforma;
        UPDATE Plataforma SET qtd_users = qtd_users + 1 WHERE nro = NEW.nro_plataforma;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER platusuario_qtd AFTER INSERT OR UPDATE OF nro_plataforma OR DELETE ON PlataformaUsuario
FOR EACH ROW EXECUTE FUNCTION trg_platusuario();

-- T9: o dono do canal nao e registrado como participante convidado
CREATE OR REPLACE FUNCTION trg_participa_dono() RETURNS trigger AS $$
DECLARE
    v_dono Canal.id_streamer%TYPE;
BEGIN
    SELECT c.id_streamer INTO v_dono
      FROM Video v JOIN Canal c ON c.id_canal = v.id_canal
     WHERE v.id_video = NEW.id_video;

    IF v_dono = NEW.id_streamer THEN
        RAISE EXCEPTION 'Streamer % e dono do canal do video %; nao registrar em Participa',
            NEW.id_streamer, NEW.id_video;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER participa_dono_bi BEFORE INSERT OR UPDATE ON Participa
FOR EACH ROW EXECUTE FUNCTION trg_participa_dono();

-- T10: cada canal deve ter exatamente cinco niveis de membro,
-- verificado no fim da transacao
CREATE OR REPLACE FUNCTION trg_canal_cinco_niveis() RETURNS trigger AS $$
DECLARE
    v_canal INTEGER;
    v_qtd   INTEGER;
BEGIN
    v_canal := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_canal ELSE NEW.id_canal END;

    IF NOT EXISTS (SELECT 1 FROM Canal WHERE id_canal = v_canal) THEN
        RETURN NULL;
    END IF;

    SELECT COUNT(*) INTO v_qtd FROM NivelCanal WHERE id_canal = v_canal;
    IF v_qtd <> 5 THEN
        RAISE EXCEPTION 'Canal % deve ter exatamente 5 niveis de membro (encontrados %)', v_canal, v_qtd;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER nivelcanal_cinco AFTER INSERT OR UPDATE OR DELETE ON NivelCanal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_canal_cinco_niveis();

CREATE CONSTRAINT TRIGGER canal_cinco_niveis AFTER INSERT ON Canal
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION trg_canal_cinco_niveis();

-- Rede de seguranca: recalcula os derivados a partir dos dados reais.
-- Usar apos cargas em massa feitas com as triggers desabilitadas.
CREATE OR REPLACE FUNCTION recalcular_derivados() RETURNS void AS $$
BEGIN
    UPDATE Canal c
       SET qtd_videos = s.vid, qtd_visualizacoes = s.vis
      FROM (SELECT ca.id_canal,
                   COUNT(v.id_video)                 AS vid,
                   COALESCE(SUM(v.visu_total), 0)    AS vis
              FROM Canal ca LEFT JOIN Video v ON v.id_canal = ca.id_canal
             GROUP BY ca.id_canal) AS s
     WHERE s.id_canal = c.id_canal
       AND (c.qtd_videos <> s.vid OR c.qtd_visualizacoes <> s.vis);

    UPDATE Plataforma p
       SET qtd_users = s.n
      FROM (SELECT pl.nro, COUNT(pu.id_usuario) AS n
              FROM Plataforma pl
              LEFT JOIN PlataformaUsuario pu ON pu.nro_plataforma = pl.nro
             GROUP BY pl.nro) AS s
     WHERE s.nro = p.nro AND p.qtd_users <> s.n;
END;
$$ LANGUAGE plpgsql;
