\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

DROP TABLE IF EXISTS StreamerPais, PlataformaUsuario, Usuario,
                     Plataforma, EmpresaPais, Empresa, Pais, Conversao CASCADE;

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

CREATE TABLE Empresa (
    nro INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    nome_fantasia VARCHAR(100)
);

CREATE TABLE EmpresaPais (
    nro_empresa INTEGER NOT NULL REFERENCES Empresa(nro) ON DELETE CASCADE,
    ddi_pais INTEGER NOT NULL REFERENCES Pais(DDI),
    id_nacional VARCHAR(30) NOT NULL,
    PRIMARY KEY (nro_empresa, ddi_pais),
    CONSTRAINT uq_empresapais_idnacional UNIQUE (ddi_pais, id_nacional)
);

CREATE TABLE Plataforma (
    nro INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome VARCHAR(100) NOT NULL UNIQUE,
    qtd_users BIGINT NOT NULL DEFAULT 0,
    empresa_fund INTEGER NOT NULL REFERENCES Empresa(nro),
    empresa_respo INTEGER NOT NULL REFERENCES Empresa(nro),
    data_fund DATE NOT NULL,
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users >= 0)
);

-- nick é a chave do modelo; id_usuario é o identificador artificial usado nas FKs
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

CREATE TABLE StreamerPais (
    id_streamer INTEGER NOT NULL REFERENCES Usuario(id_usuario) ON DELETE CASCADE,
    ddi_pais INTEGER NOT NULL REFERENCES Pais(DDI),
    nro_passaporte VARCHAR(30) NOT NULL,
    PRIMARY KEY (id_streamer, ddi_pais),
    CONSTRAINT uq_streamer_passaporte UNIQUE (ddi_pais, nro_passaporte)
);

COMMENT ON COLUMN Plataforma.qtd_users IS 'Derivado: COUNT(PlataformaUsuario). Recalculo periodico.';
