\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP TABLE IF EXISTS MecanismoPlat, CartaoCredito, PayPal, BitCoin, Doacao,
                     Comentario, Participa, Video,
                     Inscricao, NivelCanal, Patrocinio, Canal,
                     StreamerPais, PlataformaUsuario, Usuario,
                     Plataforma, Empresa, Pais, Conversao CASCADE;

CREATE TABLE Conversao (
    moeda CHAR(3) PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    fator_conver NUMERIC(18,8) NOT NULL,
    CONSTRAINT ck_conversao_fator CHECK (fator_conver > 0)
);

CREATE TABLE Pais (
    DDI INTEGER PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    moeda CHAR(3) NOT NULL REFERENCES Conversao(moeda)
);

-- ALTERADO: EmpresaPais incorporada (a relacao era 1:1 com Empresa)
CREATE TABLE Empresa (
    nro INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    nome_fantasia VARCHAR(100),
    ddi_pais INTEGER NOT NULL REFERENCES Pais(DDI),
    id_nacional VARCHAR(30) NOT NULL,
    CONSTRAINT uq_empresa_id_nacional UNIQUE (ddi_pais, id_nacional)
);

CREATE TABLE Plataforma (
    nro INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    qtd_users BIGINT NOT NULL DEFAULT 0,
    empresa_fund INTEGER NOT NULL REFERENCES Empresa(nro),
    empresa_respo INTEGER NOT NULL REFERENCES Empresa(nro),
    data_fund DATE NOT NULL,
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users >= 0)
) WITH (fillfactor = 70);

-- ALTERADO: id_usuario artificial como PK; nick preservado como chave candidata
CREATE TABLE Usuario (
    id_usuario INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nick VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    data_nasc DATE NOT NULL,
    telefone VARCHAR(20) NOT NULL,
    end_postal VARCHAR(200),
    pais_residencia INTEGER NOT NULL REFERENCES Pais(DDI)
);

CREATE TABLE PlataformaUsuario (
    nro_plataforma INTEGER NOT NULL REFERENCES Plataforma(nro),
    id_usuario INTEGER NOT NULL REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    nro_usuario BIGINT NOT NULL,
    PRIMARY KEY (nro_plataforma, id_usuario),
    CONSTRAINT uq_platusuario_nro UNIQUE (nro_plataforma, nro_usuario)
);

-- ALTERADO: PK apenas id_streamer. O enunciado cita um passaporte e um pais de
-- passaporte por streamer, e a PK simples permite que Canal e Participa
-- referenciem esta tabela, garantindo a especializacao sem trigger.
CREATE TABLE StreamerPais (
    id_streamer INTEGER PRIMARY KEY REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    ddi_pais INTEGER NOT NULL REFERENCES Pais(DDI),
    nro_passaporte VARCHAR(30) NOT NULL,
    CONSTRAINT uq_streamer_passaporte UNIQUE (ddi_pais, nro_passaporte)
);

-- ALTERADO: id_canal artificial; id_streamer referencia StreamerPais
CREATE TABLE Canal (
    id_canal INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    nro_plataforma INTEGER NOT NULL REFERENCES Plataforma(nro),
    id_streamer INTEGER NOT NULL REFERENCES StreamerPais(id_streamer),
    tipo VARCHAR(10) NOT NULL,
    data_inicio DATE NOT NULL,
    descricao TEXT,
    qtd_videos INTEGER NOT NULL DEFAULT 0,
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT uq_canal_nome_plataforma UNIQUE (nro_plataforma, nome),
    CONSTRAINT ck_canal_tipo CHECK (tipo IN ('privado', 'publico', 'misto')),
    CONSTRAINT ck_canal_qtd_vid CHECK (qtd_videos >= 0),
    CONSTRAINT ck_canal_qtd_vis CHECK (qtd_visualizacoes >= 0)
) WITH (fillfactor = 70);

CREATE TABLE Patrocinio (
    nro_empresa INTEGER NOT NULL REFERENCES Empresa(nro) ON DELETE CASCADE,
    id_canal INTEGER NOT NULL REFERENCES Canal(id_canal) ON DELETE CASCADE,
    valor NUMERIC(14,2) NOT NULL,
    PRIMARY KEY (nro_empresa, id_canal),
    CONSTRAINT ck_patrocinio_valor CHECK (valor > 0)
);

-- ALTERADO: adicionado o nome do nivel, exigido pelo enunciado;
-- gif armazenado como caminho de arquivo
CREATE TABLE NivelCanal (
    id_canal INTEGER NOT NULL REFERENCES Canal(id_canal) ON DELETE CASCADE,
    nivel SMALLINT NOT NULL,
    nome VARCHAR(50) NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    gif VARCHAR(255) NOT NULL,
    PRIMARY KEY (id_canal, nivel),
    CONSTRAINT uq_nivel_nome UNIQUE (id_canal, nome),
    CONSTRAINT ck_nivel_faixa CHECK (nivel BETWEEN 1 AND 5),
    CONSTRAINT ck_nivel_valor CHECK (valor >= 0),
    CONSTRAINT ck_nivel_gif CHECK (gif LIKE '%.gif')
);

-- ALTERADO: removida a FK redundante para Canal; a FK composta para
-- NivelCanal ja garante a existencia do canal
CREATE TABLE Inscricao (
    id_canal INTEGER NOT NULL,
    id_membro INTEGER NOT NULL REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    nivel SMALLINT NOT NULL,
    PRIMARY KEY (id_canal, id_membro),
    CONSTRAINT fk_inscricao_nivel FOREIGN KEY (id_canal, nivel)
        REFERENCES NivelCanal(id_canal, nivel) ON DELETE CASCADE
);

-- ALTERADO: id_video artificial; chave natural preservada como UNIQUE
CREATE TABLE Video (
    id_video INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_canal INTEGER NOT NULL REFERENCES Canal(id_canal) ON DELETE CASCADE,
    titulo VARCHAR(200) NOT NULL,
    dataH TIMESTAMP NOT NULL,
    tema VARCHAR(100) NOT NULL,
    duracao INTERVAL NOT NULL,
    visu_simul INTEGER NOT NULL DEFAULT 0,
    visu_total BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT uq_video_canal_data_titulo UNIQUE (id_canal, dataH, titulo),
    CONSTRAINT ck_video_duracao CHECK (duracao > INTERVAL '0'),
    CONSTRAINT ck_video_visu CHECK (visu_simul >= 0 AND visu_total >= 0 AND visu_simul <= visu_total)
) WITH (fillfactor = 85);

-- ALTERADO: id_streamer referencia StreamerPais. Participa registra apenas os
-- streamers convidados; o dono do canal esta em Canal.id_streamer.
CREATE TABLE Participa (
    id_video INTEGER NOT NULL REFERENCES Video(id_video) ON DELETE CASCADE,
    id_streamer INTEGER NOT NULL REFERENCES StreamerPais(id_streamer) ON DELETE CASCADE,
    PRIMARY KEY (id_video, id_streamer)
);

-- ALTERADO: PK (id_video, seq). O enunciado define o sequencial como dependente
-- apenas do video; id_usuario e atributo determinado pelo comentario.
CREATE TABLE Comentario (
    id_video INTEGER NOT NULL REFERENCES Video(id_video) ON DELETE CASCADE,
    seq INTEGER NOT NULL,
    id_usuario INTEGER NOT NULL REFERENCES Usuario(id_usuario) ON DELETE RESTRICT,
    texto TEXT NOT NULL,
    dataH TIMESTAMP NOT NULL,
    coment_on BOOLEAN NOT NULL,
    PRIMARY KEY (id_video, seq),
    CONSTRAINT ck_comentario_seq CHECK (seq > 0)
);

-- ALTERADO: id_doacao artificial; id_usuario removido da chave, pois o
-- comentario ja o determina funcionalmente
CREATE TABLE Doacao (
    id_doacao INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_video INTEGER NOT NULL,
    seq_comentario INTEGER NOT NULL,
    seq_doacao INTEGER NOT NULL,
    valor NUMERIC(14,2) NOT NULL,
    status VARCHAR(10) NOT NULL,
    CONSTRAINT uq_doacao_natural UNIQUE (id_video, seq_comentario, seq_doacao),
    CONSTRAINT fk_doacao_comentario FOREIGN KEY (id_video, seq_comentario)
        REFERENCES Comentario(id_video, seq) ON DELETE CASCADE,
    CONSTRAINT ck_doacao_seq CHECK (seq_doacao > 0),
    CONSTRAINT ck_doacao_valor CHECK (valor > 0),
    CONSTRAINT ck_doacao_status CHECK (status IN ('recusado', 'recebido', 'lido'))
);

CREATE TABLE BitCoin (
    id_doacao INTEGER PRIMARY KEY REFERENCES Doacao(id_doacao) ON DELETE CASCADE,
    TxID VARCHAR(128) NOT NULL UNIQUE
);

CREATE TABLE PayPal (
    id_doacao INTEGER PRIMARY KEY REFERENCES Doacao(id_doacao) ON DELETE CASCADE,
    IdPayPal VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE CartaoCredito (
    id_doacao INTEGER PRIMARY KEY REFERENCES Doacao(id_doacao) ON DELETE CASCADE,
    nro VARCHAR(25) NOT NULL,
    bandeira VARCHAR(30) NOT NULL,
    dataH TIMESTAMP NOT NULL
);

-- ALTERADO: nro_plataforma removido; e determinado pelo canal do video
CREATE TABLE MecanismoPlat (
    id_doacao INTEGER PRIMARY KEY REFERENCES Doacao(id_doacao) ON DELETE CASCADE,
    seq_plataforma INTEGER NOT NULL,
    CONSTRAINT ck_mecplat_seq CHECK (seq_plataforma > 0)
);

COMMENT ON COLUMN Plataforma.qtd_users        IS 'Derivado: COUNT(PlataformaUsuario). Mantido por trigger.';
COMMENT ON COLUMN Canal.qtd_videos            IS 'Derivado: COUNT(Video). Mantido por trigger.';
COMMENT ON COLUMN Canal.qtd_visualizacoes     IS 'Derivado: SUM(Video.visu_total). Mantido por trigger.';
COMMENT ON COLUMN Doacao.valor                IS 'Moeda do pais de residencia do doador; converter por Conversao.fator_conver.';
COMMENT ON COLUMN NivelCanal.valor            IS 'Moeda do pais de residencia do dono do canal; converter por Conversao.fator_conver.';
COMMENT ON COLUMN Patrocinio.valor            IS 'Ja expresso em dolares americanos, conforme o enunciado.';
