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

INSERT INTO Patrocinio (nro_empresa, id_canal, valor)
SELECT 1 + floor(random() * e.ne)::int,
       1 + floor(c.nc * power(random(), 2))::int,
       round(power(10, 2.7 + random() * 2.6)::numeric, 2)
FROM generate_series(1, 3400 + floor(random() * 300)::int),
     (SELECT count(*) AS ne FROM Empresa) AS e, (SELECT count(*) AS nc FROM Canal) AS c
ON CONFLICT DO NOTHING;

-- o dono não é membro do próprio canal; níveis baratos são mais comuns
INSERT INTO Inscricao (id_canal, id_membro, nivel)
SELECT s.id_canal, s.id_membro, 1 + floor(5 * power(random(), 2.5))::int
FROM (
    SELECT 1 + floor(c.nc * power(random(), 2))::int AS id_canal,
           1 + floor(random() * u.nu)::int AS id_membro
    FROM generate_series(1, 10600 + floor(random() * 300)::int),
         (SELECT count(*) AS nc FROM Canal) AS c, (SELECT count(*) AS nu FROM Usuario) AS u
) AS s
JOIN Canal c ON c.id_canal = s.id_canal AND c.id_streamer <> s.id_membro
ON CONFLICT DO NOTHING;

INSERT INTO Video (id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
SELECT c.id_canal,
       (ARRAY['Gameplay de', 'Live de', 'Jogando', 'Torneio de', 'Speedrun de', 'Review de', 'Rankeada de',
              'Maratona de'])[1 + floor(random() * 8)::int] || ' ' || j.nome || ' #' || (1 + floor(random() * 300))::int,
       c.data_inicio + random() * (TIMESTAMP '2026-10-31' - c.data_inicio),
       j.tema,
       make_interval(mins => 3 + floor(power(random(), 1.3) * 420)::int),
       floor(s.visu * (0.01 + random() * 0.3))::int,
       s.visu
FROM (
    SELECT 1 + floor(c.nc * power(random(), 2))::int AS id_canal,
           1 + floor(random() * 24)::int AS jogo,
           floor(power(10, 1.7 + random() * 5))::bigint AS visu
    FROM generate_series(1, 10600 + floor(random() * 400)::int), (SELECT count(*) AS nc FROM Canal) AS c
) AS s
JOIN Canal c ON c.id_canal = s.id_canal
JOIN (VALUES
    (1, 'Minecraft', 'Sandbox'), (2, 'League of Legends', 'MOBA'), (3, 'Valorant', 'FPS'),
    (4, 'Counter-Strike 2', 'FPS'), (5, 'Fortnite', 'Battle Royale'), (6, 'GTA V', 'Mundo aberto'),
    (7, 'EA FC 26', 'Esporte'), (8, 'Elden Ring', 'RPG'), (9, 'Dota 2', 'MOBA'),
    (10, 'Apex Legends', 'Battle Royale'), (11, 'Rocket League', 'Esporte'), (12, 'Overwatch 2', 'FPS'),
    (13, 'Hollow Knight', 'Indie'), (14, 'Stardew Valley', 'Simulação'), (15, 'Free Fire', 'Battle Royale'),
    (16, 'Call of Duty: Warzone', 'Battle Royale'), (17, 'The Sims 4', 'Simulação'), (18, 'Among Us', 'Party'),
    (19, 'Roblox', 'Sandbox'), (20, 'Baldur''s Gate 3', 'RPG'), (21, 'Hades II', 'Indie'),
    (22, 'Celeste', 'Indie'), (23, 'Age of Empires IV', 'Estratégia'), (24, 'Civilization VII', 'Estratégia')
) AS j(id, nome, tema) ON j.id = s.jogo;

INSERT INTO Participa (id_video, id_streamer)
SELECT s.id_video, t.id_usuario
FROM (
    SELECT 1 + floor(random() * v.nv)::int AS id_video, 1 + floor(random() * st.ns)::int AS n
    FROM generate_series(1, 3500 + floor(random() * 300)::int),
         (SELECT count(*) AS nv FROM Video) AS v, (SELECT count(*) AS ns FROM tmp_streamer) AS st
) AS s
JOIN tmp_streamer t ON t.n = s.n
JOIN Video v ON v.id_video = s.id_video
JOIN Canal c ON c.id_canal = v.id_canal AND c.id_streamer <> t.id_usuario
ON CONFLICT DO NOTHING;

-- cada par (vídeo, usuário) sorteado rende de 1 a 4 comentários;
-- o online cai durante a transmissão e o offline, até 120 dias depois
CREATE TEMP TABLE tmp_coment ON COMMIT DROP AS
SELECT id_video, id_usuario, coment_on, dataH,
       row_number() OVER (PARTITION BY id_video, id_usuario ORDER BY dataH) AS seq
FROM (
    SELECT c.id_video, c.id_usuario, c.coment_on,
           CASE WHEN c.coment_on THEN c.inicio + c.r * c.duracao
                ELSE c.inicio + c.duracao + c.r * INTERVAL '120 days' END AS dataH
    FROM (
        SELECT s.id_video, s.id_usuario, v.dataH AS inicio, v.duracao,
               random() < 0.6 AS coment_on, random() AS r
        FROM (
            SELECT 1 + floor(v.nv * power(random(), 2))::int AS id_video,
                   1 + floor(u.nu * power(random(), 2))::int AS id_usuario,
                   1 + floor(4 * power(random(), 3))::int AS qtd
            FROM generate_series(1, 6700 + floor(random() * 300)::int),
                 (SELECT count(*) AS nv FROM Video) AS v, (SELECT count(*) AS nu FROM Usuario) AS u
        ) AS s
        CROSS JOIN generate_series(1, s.qtd)
        JOIN Video v ON v.id_video = s.id_video
    ) AS c
) AS t;

INSERT INTO Comentario (id_video, id_usuario, seq, texto, dataH, coment_on)
SELECT id_video, id_usuario, seq,
       (ARRAY['GG!', 'Que jogada!', 'kkkkkkkk', 'Salve do Rio!', 'Primeiro!', 'Qual é o seu setup?',
              'Muito bom o vídeo', 'Traz mais desse jogo', 'F', 'Clipa isso!', 'Boa noite, chat',
              'Esse boss é impossível', 'Joga com os inscritos', 'Melhor live da semana', 'Tá de hack?',
              'Faltou o link do torneio'])[1 + floor(random() * 16)::int],
       dataH, coment_on
FROM tmp_coment;

-- quase metade dos comentários traz doação e poucos trazem duas;
-- o valor é sorteado em dólar e gravado na moeda do país do doador
CREATE TEMP TABLE tmp_doacao ON COMMIT DROP AS
SELECT t.id_video, t.id_usuario, t.seq AS seq_comentario, k AS seq_pg, t.dataH,
       round((power(10, random() * 2.5) / cv.fator_conver)::numeric, 2) AS valor,
       random() AS r_status, random() AS r_forma
FROM (SELECT *, (random() < 0.45)::int * (1 + (random() < 0.07)::int) AS qtd FROM tmp_coment) AS t
CROSS JOIN generate_series(1, t.qtd) AS k
JOIN Usuario u ON u.id_usuario = t.id_usuario
JOIN Pais pa ON pa.DDI = u.pais_residencia
JOIN Conversao cv ON cv.moeda = pa.moeda;

INSERT INTO Doacao (id_video, id_usuario, seq_comentario, seq_pg, valor, status)
SELECT id_video, id_usuario, seq_comentario, seq_pg, valor,
       CASE WHEN r_status < 0.08 THEN 'recusado' WHEN r_status < 0.38 THEN 'recebido' ELSE 'lido' END
FROM tmp_doacao;

INSERT INTO MecanismoPlat (id_doacao, seq_plataforma)
SELECT d.id_doacao,
       row_number() OVER (PARTITION BY d.id_video, d.id_usuario, d.seq_comentario ORDER BY d.seq_pg)
FROM tmp_doacao t
JOIN Doacao d USING (id_video, id_usuario, seq_comentario, seq_pg)
WHERE t.r_forma < 0.34;

INSERT INTO CartaoCredito (id_doacao, nro, bandeira, dataH)
SELECT s.id_doacao,
       (ARRAY['4', '5', '6', '3'])[s.b] || lpad(floor(random() * 1e15)::bigint::text, 15, '0'),
       (ARRAY['Visa', 'Mastercard', 'Elo', 'Amex'])[s.b],
       s.dataH
FROM (
    SELECT d.id_doacao, t.dataH, 1 + floor(4 * power(random(), 1.6))::int AS b
    FROM tmp_doacao t
    JOIN Doacao d USING (id_video, id_usuario, seq_comentario, seq_pg)
    WHERE t.r_forma >= 0.34 AND t.r_forma < 0.58
) AS s;

INSERT INTO PayPal (id_doacao, IdPayPal)
SELECT d.id_doacao, 'PAYID-' || upper(substr(md5(random()::text), 1, 24))
FROM tmp_doacao t
JOIN Doacao d USING (id_video, id_usuario, seq_comentario, seq_pg)
WHERE t.r_forma >= 0.58 AND t.r_forma < 0.80;

INSERT INTO BitCoin (id_doacao, TxID)
SELECT d.id_doacao, md5(random()::text) || md5(random()::text)
FROM tmp_doacao t
JOIN Doacao d USING (id_video, id_usuario, seq_comentario, seq_pg)
WHERE t.r_forma >= 0.80;

UPDATE Canal c
SET qtd_videos = s.n, qtd_visualizacoes = s.v
FROM (SELECT id_canal, count(*) AS n, sum(visu_total) AS v FROM Video GROUP BY id_canal) AS s
WHERE s.id_canal = c.id_canal;

UPDATE Plataforma p
SET qtd_users = s.n
FROM (SELECT nro_plataforma, count(*) AS n FROM PlataformaUsuario GROUP BY nro_plataforma) AS s
WHERE s.nro_plataforma = p.nro;

COMMIT;

-- os dois UPDATEs acima deixaram uma versão morta de cada tupla
VACUUM FULL Canal, Plataforma;
ANALYZE;

SELECT 'Conversao' AS tabela, count(*) AS tuplas FROM Conversao UNION ALL
SELECT 'Pais', count(*) FROM Pais UNION ALL
SELECT 'Empresa', count(*) FROM Empresa UNION ALL
SELECT 'EmpresaPais', count(*) FROM EmpresaPais UNION ALL
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
