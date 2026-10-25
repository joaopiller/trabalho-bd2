\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

BEGIN;

-- semente fixa: os dados são sorteados, mas a carga sai igual em toda execução
SELECT setseed(0.2026);

INSERT INTO Conversao (moeda, nome, fator_conver) VALUES
    ('USD', 'Dólar americano', 1), ('BRL', 'Real', 0.18), ('EUR', 'Euro', 1.08),
    ('GBP', 'Libra esterlina', 1.27), ('JPY', 'Iene', 0.0067), ('KRW', 'Won', 0.00073),
    ('MXN', 'Peso mexicano', 0.055), ('ARS', 'Peso argentino', 0.001), ('INR', 'Rúpia indiana', 0.012),
    ('CNY', 'Yuan', 0.14), ('CAD', 'Dólar canadense', 0.73), ('AUD', 'Dólar australiano', 0.66),
    ('RUB', 'Rublo', 0.011);

INSERT INTO Conversao (moeda, nome, fator_conver)
SELECT moeda, 'Moeda ' || moeda, round(power(10, random() * 4 - 3.5)::numeric, 6)
FROM (
    SELECT DISTINCT chr(65 + floor(random() * 26)::int) || chr(65 + floor(random() * 26)::int)
                    || chr(65 + floor(random() * 26)::int) AS moeda
    FROM generate_series(1, 1100)
) AS s
ON CONFLICT DO NOTHING;

INSERT INTO Pais (DDI, nome, moeda)
SELECT g.ddi,
       COALESCE(r.nome, 'País ' || g.ddi),
       COALESCE(r.moeda, m.codigos[1 + floor(random() * cardinality(m.codigos))::int])
FROM generate_series(1, 1020 + floor(random() * 60)::int) AS g(ddi)
CROSS JOIN (SELECT array_agg(moeda) AS codigos FROM Conversao) AS m
LEFT JOIN (VALUES
    (1, 'Estados Unidos', 'USD'), (7, 'Rússia', 'RUB'), (33, 'França', 'EUR'), (34, 'Espanha', 'EUR'),
    (39, 'Itália', 'EUR'), (44, 'Reino Unido', 'GBP'), (49, 'Alemanha', 'EUR'), (52, 'México', 'MXN'),
    (54, 'Argentina', 'ARS'), (55, 'Brasil', 'BRL'), (61, 'Austrália', 'AUD'), (81, 'Japão', 'JPY'),
    (82, 'Coreia do Sul', 'KRW'), (86, 'China', 'CNY'), (91, 'Índia', 'INR'), (351, 'Portugal', 'EUR')
) AS r(ddi, nome, moeda) ON r.ddi = g.ddi;

-- a maior parte do público vem de poucos países
CREATE FUNCTION pg_temp.pais_aleatorio() RETURNS integer AS $$
    SELECT CASE WHEN random() < 0.7
                THEN (ARRAY[55, 55, 55, 1, 1, 44, 49, 33, 34, 81, 82, 351, 52, 54, 91, 7])[1 + floor(random() * 16)::int]
                ELSE 1 + floor(random() * (SELECT count(*) FROM Pais))::int
           END;
$$ LANGUAGE sql VOLATILE;

INSERT INTO Empresa (nome, nome_fantasia)
SELECT nome || ' ' || (ARRAY['S.A.', 'Ltda.', 'Inc.', 'GmbH', 'Corp.'])[1 + floor(random() * 5)::int],
       CASE WHEN random() < 0.7 THEN nome END
FROM (
    SELECT (ARRAY['Nova', 'Alfa', 'Prime', 'Delta', 'Hyper', 'Turbo', 'Pixel', 'Orion', 'Vértice', 'Atlas',
                  'Lumen', 'Zênite', 'Polar', 'Titan', 'Aurora', 'Quantum'])[1 + floor(random() * 16)::int]
           || ' ' ||
           (ARRAY['Games', 'Energy', 'Hardware', 'Telecom', 'Bank', 'Foods', 'Wear', 'Studios', 'Periféricos',
                  'Bebidas', 'Seguros', 'Tech', 'Mídia', 'Motors'])[1 + floor(random() * 14)::int] AS nome
    FROM generate_series(1, 3000 + floor(random() * 400)::int)
) AS s;

-- toda empresa tem sede em um país; algumas em mais de um
INSERT INTO EmpresaPais (nro_empresa, ddi_pais, id_nacional)
SELECT e.nro, pg_temp.pais_aleatorio(), lpad(floor(random() * 1e14)::bigint::text, 14, '0')
FROM (SELECT nro, 1 + (random() < 0.18)::int + (random() < 0.05)::int AS qtd FROM Empresa) AS e,
     generate_series(1, e.qtd)
ON CONFLICT DO NOTHING;

INSERT INTO Plataforma (nome, empresa_fund, empresa_respo, data_fund)
SELECT s.nome, s.fund,
       CASE WHEN random() < 0.75 THEN s.fund ELSE 1 + floor(random() * s.ne)::int END,
       COALESCE(s.data_fund, DATE '1998-01-01' + floor(random() * 9800)::int)
FROM (
    SELECT n.nome, n.data_fund, n.ord, e.ne, 1 + floor(random() * e.ne)::int AS fund
    FROM (
        SELECT nome, data_fund, ord
        FROM (VALUES ('YouTube', DATE '2005-02-14', 1), ('Twitch', DATE '2011-06-06', 2), ('Kick', DATE '2022-12-01', 3),
                     ('Facebook Gaming', DATE '2018-06-01', 4), ('TikTok Live', DATE '2019-08-01', 5),
                     ('Trovo', DATE '2020-03-01', 6), ('Rumble', DATE '2013-10-01', 7), ('Bilibili', DATE '2009-06-26', 8),
                     ('SOOP', DATE '2006-03-09', 9), ('Nimo TV', DATE '2018-04-01', 10), ('DLive', DATE '2017-12-01', 11),
                     ('Bigo Live', DATE '2016-03-01', 12)) AS r(nome, data_fund, ord)
        UNION ALL
        (SELECT p || s, NULL, 100
         FROM unnest(ARRAY['Stream', 'Play', 'Game', 'Live', 'Pixel', 'Turbo', 'Nova', 'Hyper', 'Mega', 'Ultra',
                           'Neo', 'Pro', 'Arena', 'Clip', 'Cast', 'Vibe', 'Wave', 'Rush', 'Loot', 'Quest',
                           'Lobby', 'Combo', 'Frag', 'Spawn', 'Ping', 'Glitch', 'Raid', 'Bit', 'Volt', 'Zen',
                           'Echo', 'Flux', 'Orbit', 'Nitro', 'Apex', 'Drift']) AS p,
              unnest(ARRAY['Hub', 'Zone', 'TV', 'Now', 'Plus', 'Go', 'Box', 'Space', 'Verse', 'Land', 'Base',
                           'Spot', 'Point', 'Deck', 'Dock', 'Lab', 'Net', 'Link', 'Flow', 'Room', 'Stage',
                           'Channel', 'Line', 'On', 'Up', 'Max', 'One', 'X', 'Central', 'Fy', 'Ly', 'Station']) AS s
         ORDER BY random()
         LIMIT 1040 + floor(random() * 60)::int)
    ) AS n, (SELECT count(*) AS ne FROM Empresa) AS e
) AS s
ORDER BY s.ord;

INSERT INTO Usuario (nick, email, data_nasc, telefone, end_postal, pais_residencia)
SELECT nick,
       lower(nick) || '@' || (ARRAY['gmail.com', 'outlook.com', 'yahoo.com', 'hotmail.com', 'proton.me', 'icloud.com'])[1 + floor(random() * 6)::int],
       DATE '2012-12-31' - floor(power(random(), 1.5) * 16000)::int,
       '+' || pais || ' ' || lpad(floor(random() * 1e10)::bigint::text, 10, '0'),
       CASE WHEN random() < 0.8
            THEN (ARRAY['Rua', 'Avenida', 'Travessa', 'Alameda'])[1 + floor(random() * 4)::int] || ' ' ||
                 (ARRAY['das Flores', 'Sete de Setembro', 'Brasil', 'Central', 'do Comércio', 'São João', 'da Paz',
                        'Paulista', 'Atlântica', 'dos Pinheiros'])[1 + floor(random() * 10)::int] || ', ' ||
                 (1 + floor(random() * 2500))::int
       END,
       pais
FROM (
    SELECT nick, pais
    FROM (
        SELECT DISTINCT ON (lower(nick)) nick, pg_temp.pais_aleatorio() AS pais
        FROM (
            SELECT (ARRAY['Dark', 'Shadow', 'Neon', 'Crazy', 'Silent', 'Mad', 'Royal', 'Lucky', 'Frozen', 'Atomic',
                          'Toxic', 'Golden', 'Rapid', 'Lone', 'Cyber', 'Night', 'Storm', 'Iron', 'Ghost', 'Fire',
                          'Mestre', 'Tio', 'Rei', 'Lord', 'Doutor', 'Capitao', 'Mini', 'Super', 'Velho', 'Zé'])[1 + floor(random() * 30)::int]
                   || (ARRAY['Wolf', 'Ninja', 'Gamer', 'Sniper', 'Dragon', 'Panda', 'Knight', 'Hunter', 'Wizard', 'Tiger',
                             'Falcon', 'Viper', 'Rider', 'Pirate', 'Samurai', 'Gorila', 'Coruja', 'Jaguar', 'Tucano', 'Capivara',
                             'Player', 'Noob', 'Slayer', 'Master', 'Killer', 'Bot', 'Fox', 'Bear', 'Shark', 'Hawk'])[1 + floor(random() * 30)::int]
                   || CASE WHEN random() < 0.92 THEN floor(random() * 1000)::int::text ELSE '' END AS nick
            FROM generate_series(1, 10900)
        ) AS a
    ) AS d
    ORDER BY random()
) AS s;

CREATE TEMP TABLE tmp_streamer ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY random()) AS n, id_usuario, pais_residencia
FROM Usuario
WHERE random() < 0.17;

-- passaporte do país onde mora; alguns têm um segundo
INSERT INTO StreamerPais (id_streamer, ddi_pais, nro_passaporte)
SELECT id_usuario,
       CASE WHEN k = 1 THEN pais_residencia ELSE pg_temp.pais_aleatorio() END,
       chr(65 + floor(random() * 26)::int) || chr(65 + floor(random() * 26)::int)
       || lpad(floor(random() * 1e7)::int::text, 7, '0')
FROM (SELECT *, 1 + (random() < 0.12)::int AS qtd FROM tmp_streamer) AS s,
     generate_series(1, s.qtd) AS k
ON CONFLICT DO NOTHING;

-- 1 a 3 canais por streamer, concentrados nas plataformas de nro mais baixo
INSERT INTO Canal (nome, nro_plataforma, id_streamer, tipo, data_inicio, descricao)
SELECT c.nome, c.nro_plataforma, c.id_streamer,
       CASE WHEN c.r < 0.7 THEN 'público' WHEN c.r < 0.9 THEN 'misto' ELSE 'privado' END,
       ini.d + floor(random() * (DATE '2026-06-30' - ini.d))::int,
       CASE WHEN random() < 0.85
            THEN (ARRAY['Lives todos os dias', 'Gameplays e reviews', 'Torneios e campeonatos', 'Só jogo indie',
                        'Rankeadas e dicas', 'Jogatina com os inscritos', 'Speedruns e desafios'])[1 + floor(random() * 7)::int]
       END
FROM (
    SELECT u.nick || (ARRAY[' TV', ' Gaming', ' Plays', ' Live', ' Clips'])[1 + ((s.n + k) % 5)::int] AS nome,
           1 + floor(p.np * power(random(), 3))::int AS nro_plataforma,
           s.id_usuario AS id_streamer,
           random() AS r
    FROM (SELECT n, id_usuario, 1 + (random() < 0.20)::int + (random() < 0.05)::int AS qtd FROM tmp_streamer) AS s
    CROSS JOIN generate_series(1, s.qtd) AS k
    JOIN Usuario u ON u.id_usuario = s.id_usuario
    CROSS JOIN (SELECT count(*) AS np FROM Plataforma) AS p
) AS c
JOIN Plataforma pl ON pl.nro = c.nro_plataforma
CROSS JOIN LATERAL (SELECT GREATEST(pl.data_fund, DATE '2011-01-01') AS d) AS ini;

INSERT INTO NivelCanal (id_canal, nivel, nome, valor, gif)
SELECT c.id_canal, n,
       (ARRAY[['Bronze', 'Prata', 'Ouro', 'Platina', 'Diamante'],
              ['Apoiador', 'Fã', 'Super Fã', 'VIP', 'Lenda'],
              ['Recruta', 'Soldado', 'Capitão', 'General', 'Comandante']])[1 + c.id_canal % 3][n],
       round((c.base * (ARRAY[1, 2, 4, 8, 20])[n])::numeric) - 0.01,
       'emotes/canal' || c.id_canal || '_nivel' || n || '.gif'
FROM (SELECT id_canal, 1.5 + random() * 4 AS base FROM Canal) AS c, generate_series(1, 5) AS n;

-- streamer tem conta onde tem canal; os demais usuários, em uma plataforma
INSERT INTO PlataformaUsuario (nro_plataforma, id_usuario, nro_usuario)
SELECT nro_plataforma, id_usuario, 10000000 + floor(random() * 9e9)::bigint
FROM (
    SELECT nro_plataforma, id_streamer AS id_usuario FROM Canal
    UNION
    SELECT 1 + floor(p.np * power(random(), 3))::int, u.id_usuario
    FROM Usuario u, (SELECT count(*) AS np FROM Plataforma) AS p
    WHERE u.id_usuario NOT IN (SELECT id_usuario FROM tmp_streamer)
) AS s
ON CONFLICT DO NOTHING;

COMMIT;

ANALYZE;
