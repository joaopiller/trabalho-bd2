\set ON_ERROR_STOP on

DROP INDEX IF EXISTS idx_canal_streamer, idx_canal_plataforma, idx_patrocinio_canal,
                     idx_inscricao_membro, idx_doacao_efetivada;

-- I1: Canal.id_streamer e uma FK, e o PostgreSQL nao cria indice automatico
-- para FK. A UNIQUE existente comeca por nro_plataforma. Atende ao filtro por
-- streamer da consulta 3 e as juncoes de mv_resumo_canal.
CREATE INDEX idx_canal_streamer ON Canal USING hash (id_streamer);

-- I2: nro_plataforma e a PRIMEIRA coluna da UNIQUE (nro_plataforma, nome),
-- entao a busca por plataforma ja seria atendida. Este indice existe pelo
-- INCLUDE: permite index-only scan nas consultas 1 e 12, que so precisam do
-- id_canal e do dono.
CREATE INDEX idx_canal_plataforma ON Canal (nro_plataforma) INCLUDE (id_canal, id_streamer);

-- I3: a PK de Patrocinio comeca por nro_empresa; o acesso pelo canal
-- (consultas 8 e 11 e o refresh de mv_resumo_canal) faria varredura sequencial.
CREATE INDEX idx_patrocinio_canal ON Patrocinio (id_canal) INCLUDE (valor);

-- I4: a PK de Inscricao comeca por id_canal; a consulta 6 agrupa por membro.
CREATE INDEX idx_inscricao_membro ON Inscricao (id_membro) INCLUDE (id_canal, nivel);

-- I5: indice parcial das doacoes efetivadas. Menor que o indice total, dispensa
-- reavaliar o status e nao e atualizado quando entra uma doacao recusada.
-- Usado no refresh de mv_resumo_canal, a operacao periodica mais cara.
CREATE INDEX idx_doacao_efetivada ON Doacao (id_video, seq_comentario)
    INCLUDE (valor)
    WHERE status IN ('recebido', 'lido');

ANALYZE;
