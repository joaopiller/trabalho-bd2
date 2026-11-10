\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

BEGIN;

SELECT setseed(0.2026);

-- Moedas reais, seguidas de moedas ficticias ate completar 1000 tuplas.
INSERT INTO Conversao (moeda, nome, fator_conver) VALUES
    ('USD', 'Dolar americano', 1), ('BRL', 'Real', 0.18), ('EUR', 'Euro', 1.08),
    ('GBP', 'Libra esterlina', 1.27), ('JPY', 'Iene', 0.0067), ('KRW', 'Won', 0.00073),
    ('MXN', 'Peso mexicano', 0.055), ('ARS', 'Peso argentino', 0.001), ('INR', 'Rupia indiana', 0.012),
    ('CNY', 'Yuan', 0.14), ('CAD', 'Dolar canadense', 0.73), ('AUD', 'Dolar australiano', 0.66),
    ('RUB', 'Rublo', 0.011);

INSERT INTO Conversao (moeda, nome, fator_conver)
SELECT s.codigo, 'Moeda ' || s.codigo, ROUND(power(10, random() * 4 - 3.5)::NUMERIC, 8)
FROM (
    SELECT chr(65 + (i / 676) % 26) || chr(65 + (i / 26) % 26) || chr(65 + i % 26) AS codigo
    FROM generate_series(0, 1999) AS i
) AS s
WHERE s.codigo NOT IN (SELECT c.moeda FROM Conversao c)
LIMIT 987;

INSERT INTO Pais (DDI, nome, moeda)
SELECT g.ddi,
       COALESCE(r.nome, 'Pais ' || g.ddi),
       COALESCE(r.moeda, m.codigos[1 + (g.ddi * 7) % array_length(m.codigos, 1)])
FROM generate_series(1, 1000) AS g(ddi)
CROSS JOIN (SELECT array_agg(moeda ORDER BY moeda) AS codigos FROM Conversao) AS m
LEFT JOIN (VALUES
    (1, 'Estados Unidos', 'USD'), (7, 'Russia', 'RUB'), (33, 'Franca', 'EUR'), (34, 'Espanha', 'EUR'),
    (39, 'Italia', 'EUR'), (44, 'Reino Unido', 'GBP'), (49, 'Alemanha', 'EUR'), (52, 'Mexico', 'MXN'),
    (54, 'Argentina', 'ARS'), (55, 'Brasil', 'BRL'), (61, 'Australia', 'AUD'), (81, 'Japao', 'JPY'),
    (82, 'Coreia do Sul', 'KRW'), (86, 'China', 'CNY'), (91, 'India', 'INR'), (351, 'Portugal', 'EUR')
) AS r(ddi, nome, moeda) ON r.ddi = g.ddi;

-- Sorteia um pais com vies para os paises reais listados acima.
CREATE FUNCTION pg_temp.pais_aleatorio() RETURNS INTEGER AS $$
    SELECT CASE WHEN random() < 0.75
                THEN (ARRAY[55, 55, 55, 1, 1, 44, 49, 33, 34, 81, 82, 351, 52, 54, 91, 7])
                     [1 + floor(random() * 16)::INT]
                ELSE 1 + floor(random() * 1000)::INT
           END;
$$ LANGUAGE sql VOLATILE;

INSERT INTO Empresa (nome, nome_fantasia, ddi_pais, id_nacional)
SELECT s.nome || ' ' || (ARRAY['S.A.', 'Ltda.', 'Inc.', 'GmbH', 'Corp.'])[1 + floor(random() * 5)::INT],
       CASE WHEN random() < 0.7 THEN s.nome END,
       pg_temp.pais_aleatorio(),
       lpad(s.i::TEXT, 14, '0')
FROM (
    SELECT i,
           (ARRAY['Nova', 'Alfa', 'Prime', 'Delta', 'Hyper', 'Turbo', 'Pixel', 'Orion', 'Vertice', 'Atlas',
                  'Lumen', 'Zenite', 'Polar', 'Titan', 'Aurora', 'Quantum'])[1 + floor(random() * 16)::INT]
           || ' ' ||
           (ARRAY['Games', 'Energy', 'Hardware', 'Telecom', 'Bank', 'Foods', 'Wear', 'Studios', 'Perifericos',
                  'Bebidas', 'Seguros', 'Tech', 'Midia', 'Motors'])[1 + floor(random() * 14)::INT] AS nome
    FROM generate_series(1, 3000) AS i
) AS s;

-- Plataformas reais primeiro: os nros 1 a 8 sao estaveis entre execucoes.
INSERT INTO Plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT p.nome,
       1 + floor(random() * 3000)::INT,
       1 + floor(random() * 3000)::INT,
       p.fund
FROM (VALUES
    ('YouTube', DATE '2005-02-14'), ('Twitch', DATE '2011-06-06'), ('Kick', DATE '2022-10-19'),
    ('TikTok Live', DATE '2019-01-01'), ('Facebook Gaming', DATE '2018-01-01'), ('Trovo', DATE '2020-01-01'),
    ('Nimo TV', DATE '2018-05-01'), ('Rumble', DATE '2013-10-01')
) AS p(nome, fund);

INSERT INTO Plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT 'Plataforma ' || i,
       1 + floor(random() * 3000)::INT,
       1 + floor(random() * 3000)::INT,
       DATE '2004-01-01' + floor(random() * 7000)::INT
FROM generate_series(1, 992) AS i;

INSERT INTO Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT s.nick,
       'u' || s.rn || '@' || (ARRAY['mail.com', 'exemplo.br', 'webmail.net'])[1 + s.rn % 3],
       DATE '1962-01-01' + floor(random() * 15500)::INT,
       '+' || (1 + floor(random() * 998)::INT) || ' 9' || lpad(s.rn::TEXT, 8, '0'),
       (ARRAY['Rua', 'Av.', 'Travessa'])[1 + floor(random() * 3)::INT] || ' ' ||
       (ARRAY['das Flores', 'Central', 'do Porto', 'Santa Rita', 'Brasil'])[1 + floor(random() * 5)::INT] ||
       ', ' || (1 + floor(random() * 2000)::INT),
       pg_temp.pais_aleatorio()
FROM (
    SELECT nick, row_number() OVER (ORDER BY nick) AS rn
    FROM (
        SELECT DISTINCT ON (lower(a.nick)) a.nick
        FROM (
            SELECT (ARRAY['Dark', 'Shadow', 'Neon', 'Crazy', 'Silent', 'Mad', 'Royal', 'Lucky', 'Frozen', 'Atomic',
                          'Toxic', 'Golden', 'Rapid', 'Lone', 'Cyber', 'Night', 'Storm', 'Iron', 'Ghost', 'Fire',
                          'Mestre', 'Tio', 'Rei', 'Lord', 'Doutor', 'Capitao', 'Mini', 'Super', 'Velho', 'Ze'])
                   [1 + floor(random() * 30)::INT]
                || (ARRAY['Wolf', 'Ninja', 'Gamer', 'Sniper', 'Dragon', 'Panda', 'Knight', 'Hunter', 'Wizard', 'Tiger',
                          'Falcon', 'Viper', 'Rider', 'Pirate', 'Samurai', 'Gorila', 'Coruja', 'Jaguar', 'Tucano', 'Capivara',
                          'Player', 'Noob', 'Slayer', 'Master', 'Killer', 'Bot', 'Fox', 'Bear', 'Shark', 'Hawk'])
                   [1 + floor(random() * 30)::INT]
                || CASE WHEN random() < 0.9 THEN floor(random() * 1000)::INT::TEXT ELSE '' END AS nick
            FROM generate_series(1, 11000)
        ) AS a
        ORDER BY lower(a.nick)
    ) AS d
    LIMIT 9000
) AS s;

INSERT INTO PlataformaUsuario (nro_plataforma, id_usuario, nro_usuario)
SELECT CASE WHEN random() < 0.78
            THEN 1 + floor(8 * power(random(), 1.4))::INT
            ELSE 1 + floor(random() * 1000)::INT
       END,
       u.id_usuario,
       u.id_usuario * 10 + k
FROM Usuario u,
     generate_series(0, CASE WHEN u.id_usuario % 12 = 0 THEN 1 ELSE 0 END) AS k
ON CONFLICT DO NOTHING;

INSERT INTO StreamerPais (id_streamer, ddi_pais, nro_passaporte)
SELECT u.id_usuario,
       CASE WHEN random() < 0.85 THEN u.pais_residencia ELSE pg_temp.pais_aleatorio() END,
       chr(65 + floor(random() * 26)::INT) || chr(65 + floor(random() * 26)::INT)
       || lpad(floor(random() * 1e7)::INT::TEXT, 7, '0')
FROM Usuario u
WHERE u.id_usuario % 6 = 0
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE tmp_streamer ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY id_streamer) AS rn, id_streamer FROM StreamerPais;

-- Canais concentrados nas plataformas reais e em uma minoria de streamers.
INSERT INTO Canal (nome, nro_plataforma, id_streamer, tipo, data_inicio, descricao)
SELECT (ARRAY['Arena', 'Covil', 'Base', 'Mundo', 'Cantinho', 'Clube', 'Reino', 'Central', 'Esquina', 'Toca'])
           [1 + floor(random() * 10)::INT]
       || ' ' ||
       (ARRAY['do Dragao', 'da Coruja', 'Gamer', 'Retro', 'do Lobo', 'Indie', 'Competitivo', 'da Madrugada',
              'dos Noobs', 'Supremo'])[1 + floor(random() * 10)::INT]
       || ' #' || s.i,
       CASE WHEN random() < 0.8
            THEN 1 + floor(8 * power(random(), 1.4))::INT
            ELSE 1 + floor(random() * 1000)::INT
       END,
       t.id_streamer,
       (ARRAY['publico', 'publico', 'publico', 'misto', 'privado'])[1 + floor(random() * 5)::INT],
       DATE '2011-01-01' + floor(random() * 5000)::INT,
       'Canal dedicado a jogos online.'
FROM (
    SELECT i, 1 + floor(n.total * power(random(), 1.6))::INT AS rn
    FROM generate_series(1, 1800) AS i,
         (SELECT count(*) AS total FROM tmp_streamer) AS n
) AS s
JOIN tmp_streamer t ON t.rn = s.rn;

INSERT INTO NivelCanal (id_canal, nivel, nome, valor, gif)
SELECT c.id_canal,
       n,
       (ARRAY['Bronze', 'Prata', 'Ouro', 'Platina', 'Diamante'])[n],
       ROUND((c.base * n)::NUMERIC, 2),
       'gifs/canal' || c.id_canal || '_nivel' || n || '.gif'
FROM (SELECT id_canal, 4.99 + random() * 12 AS base FROM Canal) AS c,
     generate_series(1, 5) AS n;

INSERT INTO Patrocinio (nro_empresa, id_canal, valor)
SELECT 1 + floor(random() * e.ne)::INT,
       1 + floor(c.nc * power(random(), 2))::INT,
       ROUND(power(10, 2.7 + random() * 2.6)::NUMERIC, 2)
FROM generate_series(1, 3000),
     (SELECT count(*) AS ne FROM Empresa) AS e,
     (SELECT count(*) AS nc FROM Canal) AS c
ON CONFLICT DO NOTHING;

INSERT INTO Inscricao (id_canal, id_membro, nivel)
SELECT s.id_canal, s.id_membro, 1 + floor(5 * power(random(), 2.5))::INT
FROM (
    SELECT 1 + floor(c.nc * power(random(), 2))::INT AS id_canal,
           1 + floor(random() * u.nu)::INT AS id_membro
    FROM generate_series(1, 10000),
         (SELECT count(*) AS nc FROM Canal) AS c,
         (SELECT count(*) AS nu FROM Usuario) AS u
) AS s
JOIN Canal c2 ON c2.id_canal = s.id_canal AND c2.id_streamer <> s.id_membro
ON CONFLICT DO NOTHING;

INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT c.id_canal,
       (ARRAY['Gameplay de', 'Live de', 'Jogando', 'Torneio de', 'Speedrun de', 'Review de', 'Rankeada de',
              'Maratona de'])[1 + floor(random() * 8)::INT] || ' ' || j.nome || ' #' || s.i,
       c.data_inicio + random() * (TIMESTAMP '2026-10-31' - c.data_inicio),
       j.tema,
       make_interval(mins => 3 + floor(power(random(), 1.3) * 420)::INT),
       floor(s.visu * (0.01 + random() * 0.3))::INT,
       s.visu
FROM (
    SELECT i,
           1 + floor(nc.n * power(random(), 2))::INT AS id_canal,
           1 + floor(random() * 20)::INT AS jogo,
           floor(power(10, 1.7 + random() * 4))::BIGINT AS visu
    FROM generate_series(1, 9000) AS i,
         (SELECT count(*) AS n FROM Canal) AS nc
) AS s
JOIN Canal c ON c.id_canal = s.id_canal
JOIN (VALUES
    (1, 'Minecraft', 'Sandbox'), (2, 'League of Legends', 'MOBA'), (3, 'Valorant', 'FPS'),
    (4, 'Counter-Strike 2', 'FPS'), (5, 'Fortnite', 'Battle Royale'), (6, 'GTA V', 'Mundo aberto'),
    (7, 'EA FC 26', 'Esporte'), (8, 'Elden Ring', 'RPG'), (9, 'Dota 2', 'MOBA'),
    (10, 'Apex Legends', 'Battle Royale'), (11, 'Rocket League', 'Esporte'), (12, 'Overwatch 2', 'FPS'),
    (13, 'Hollow Knight', 'Indie'), (14, 'Stardew Valley', 'Simulacao'), (15, 'Free Fire', 'Battle Royale'),
    (16, 'Roblox', 'Sandbox'), (17, 'The Sims 4', 'Simulacao'), (18, 'Baldurs Gate 3', 'RPG'),
    (19, 'Among Us', 'Party'), (20, 'Terraria', 'Sandbox')
) AS j(id, nome, tema) ON j.id = s.jogo;

-- Streamers convidados (o dono do canal nao entra em Participa).
INSERT INTO Participa (id_video, id_streamer)
SELECT x.id_video, t.id_streamer
FROM (
    SELECT v.id_video,
           c.id_streamer AS dono,
           1 + floor(n.total * random())::INT AS rn
    FROM Video v
    JOIN Canal c ON c.id_canal = v.id_canal
    CROSS JOIN (SELECT count(*) AS total FROM tmp_streamer) AS n
    CROSS JOIN generate_series(1, 1 + (v.id_video % 2)) AS k
    WHERE v.id_video % 3 = 0
) AS x
JOIN tmp_streamer t ON t.rn = x.rn
WHERE t.id_streamer <> x.dono
ON CONFLICT DO NOTHING;

-- Comentarios concentrados nos videos e usuarios mais ativos.
CREATE TEMP TABLE tmp_coment ON COMMIT DROP AS
SELECT s.id_video,
       s.id_usuario,
       v.dataH + random() * (v.duracao + INTERVAL '20 days') AS dataH,
       random() < 0.62 AS coment_on
FROM (
    SELECT 1 + floor(nv.n * power(random(), 2))::INT AS id_video,
           1 + floor(nu.n * power(random(), 1.5))::INT AS id_usuario,
           1 + floor(3 * power(random(), 2.5))::INT AS qtd
    FROM generate_series(1, 6200),
         (SELECT count(*) AS n FROM Video) AS nv,
         (SELECT count(*) AS n FROM Usuario) AS nu
) AS s
CROSS JOIN generate_series(1, s.qtd)
JOIN Video v ON v.id_video = s.id_video;

CREATE TEMP TABLE tmp_coment_num ON COMMIT DROP AS
SELECT c.*,
       row_number() OVER (PARTITION BY c.id_video ORDER BY c.dataH, c.id_usuario)::INT AS seq
FROM tmp_coment c;

INSERT INTO Comentario (id_video, seq, id_usuario, texto, dataH, coment_on)
SELECT t.id_video, t.seq, t.id_usuario,
       (ARRAY['GG!', 'Que jogada!', 'kkkkkkkk', 'Salve do Rio!', 'Primeiro!', 'Qual e o seu setup?',
              'Muito bom o video', 'Traz mais desse jogo', 'F', 'Clipa isso!', 'Boa noite, chat',
              'Esse boss e impossivel', 'Joga com os inscritos', 'Melhor live da semana', 'Ta de hack?',
              'Faltou o link do torneio'])[1 + floor(random() * 16)::INT],
       t.dataH, t.coment_on
FROM tmp_coment_num t;

-- O valor e sorteado em dolares e convertido para a moeda do doador,
-- de modo que a distribuicao em USD fique realista em qualquer pais.
CREATE TEMP TABLE tmp_doacao ON COMMIT DROP AS
SELECT c.id_video,
       c.seq AS seq_comentario,
       row_number() OVER (PARTITION BY c.id_video, c.seq ORDER BY k)::INT AS seq_doacao,
       c.dataH,
       ROUND((power(10, random() * 2.5) / cv.fator_conver)::NUMERIC, 2) AS valor,
       random() AS r_status,
       random() AS r_forma
FROM (SELECT *, (random() < 0.52)::INT * (1 + (random() < 0.08)::INT) AS qtd FROM tmp_coment_num) AS c
CROSS JOIN generate_series(1, c.qtd) AS k
JOIN Usuario u   ON u.id_usuario = c.id_usuario
JOIN Pais pa     ON pa.DDI       = u.pais_residencia
JOIN Conversao cv ON cv.moeda    = pa.moeda;

INSERT INTO Doacao (id_video, seq_comentario, seq_doacao, valor, status)
SELECT t.id_video, t.seq_comentario, t.seq_doacao, t.valor,
       CASE WHEN t.r_status < 0.08 THEN 'recusado'
            WHEN t.r_status < 0.55 THEN 'recebido'
            ELSE 'lido' END
FROM tmp_doacao t;

INSERT INTO BitCoin (id_doacao, TxID)
SELECT d.id_doacao, md5(d.id_doacao::TEXT || 'btc') || md5(d.id_doacao::TEXT || 'tx')
FROM tmp_doacao t
JOIN Doacao d USING (id_video, seq_comentario, seq_doacao)
WHERE t.r_forma < 0.22;

INSERT INTO PayPal (id_doacao, IdPayPal)
SELECT d.id_doacao, 'PP-' || upper(md5(d.id_doacao::TEXT || 'pp'))
FROM tmp_doacao t
JOIN Doacao d USING (id_video, seq_comentario, seq_doacao)
WHERE t.r_forma >= 0.22 AND t.r_forma < 0.47;

INSERT INTO CartaoCredito (id_doacao, nro, bandeira, dataH)
SELECT d.id_doacao,
       lpad(((d.id_doacao * 7919) % 1000000000000)::TEXT, 16, '4'),
       (ARRAY['Visa', 'Mastercard', 'Elo', 'Amex'])[1 + (d.id_doacao % 4)],
       t.dataH
FROM tmp_doacao t
JOIN Doacao d USING (id_video, seq_comentario, seq_doacao)
WHERE t.r_forma >= 0.47 AND t.r_forma < 0.74;

INSERT INTO MecanismoPlat (id_doacao, seq_plataforma)
SELECT d.id_doacao,
       row_number() OVER (PARTITION BY t.id_video, t.seq_comentario ORDER BY t.seq_doacao)::INT
FROM tmp_doacao t
JOIN Doacao d USING (id_video, seq_comentario, seq_doacao)
WHERE t.r_forma >= 0.74;

DROP FUNCTION pg_temp.pais_aleatorio();

COMMIT;

VACUUM FULL Canal, Plataforma;
ANALYZE;

SELECT 'Conversao' AS tabela, count(*) AS tuplas FROM Conversao UNION ALL
SELECT 'Pais', count(*) FROM Pais UNION ALL
SELECT 'Empresa', count(*) FROM Empresa UNION ALL
SELECT 'Plataforma', count(*) FROM Plataforma UNION ALL
SELECT 'Usuario', count(*) FROM Usuario UNION ALL
SELECT 'PlataformaUsuario', count(*) FROM PlataformaUsuario UNION ALL
SELECT 'StreamerPais', count(*) FROM StreamerPais UNION ALL
SELECT 'Canal', count(*) FROM Canal UNION ALL
SELECT 'NivelCanal', count(*) FROM NivelCanal UNION ALL
SELECT 'Patrocinio', count(*) FROM Patrocinio UNION ALL
SELECT 'Inscricao', count(*) FROM Inscricao UNION ALL
SELECT 'Video', count(*) FROM Video UNION ALL
SELECT 'Participa', count(*) FROM Participa UNION ALL
SELECT 'Comentario', count(*) FROM Comentario UNION ALL
SELECT 'Doacao', count(*) FROM Doacao UNION ALL
SELECT 'BitCoin', count(*) FROM BitCoin UNION ALL
SELECT 'PayPal', count(*) FROM PayPal UNION ALL
SELECT 'CartaoCredito', count(*) FROM CartaoCredito UNION ALL
SELECT 'MecanismoPlat', count(*) FROM MecanismoPlat
ORDER BY 1;
