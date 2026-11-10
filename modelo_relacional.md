# Modelo Relacional

Chaves primárias listadas na tabela ao final. `UNIQUE` marca as chaves candidatas, inclusive as chaves naturais preservadas após a introdução de identificadores artificiais.

```
Conversao(moeda, nome, fator_conver)

Pais(DDI, nome, moeda)
    moeda referencia Conversao(moeda)

Empresa(nro, nome, nome_fantasia, ddi_pais, id_nacional)
    ddi_pais referencia Pais(DDI)
    UNIQUE (ddi_pais, id_nacional)

-- qtd_users é derivado e mantido por trigger
Plataforma(nro, nome, qtd_users, empresa_fund, empresa_respo, data_fund)
    empresa_fund  referencia Empresa(nro)
    empresa_respo referencia Empresa(nro)
    UNIQUE (nome)

Usuario(id_usuario, nick, email, data_nasc, telefone, end_postal, pais_residencia)
    pais_residencia referencia Pais(DDI)
    UNIQUE (nick), UNIQUE (email)

PlataformaUsuario(nro_plataforma, id_usuario, nro_usuario)
    nro_plataforma referencia Plataforma(nro)
    id_usuario     referencia Usuario(id_usuario)
    UNIQUE (nro_plataforma, nro_usuario)

StreamerPais(id_streamer, ddi_pais, nro_passaporte)
    id_streamer referencia Usuario(id_usuario)
    ddi_pais    referencia Pais(DDI)
    UNIQUE (ddi_pais, nro_passaporte)

-- qtd_videos e qtd_visualizacoes são derivados e mantidos por trigger
Canal(id_canal, nome, nro_plataforma, id_streamer, tipo, data_inicio, descricao,
      qtd_videos, qtd_visualizacoes)
    nro_plataforma referencia Plataforma(nro)
    id_streamer    referencia StreamerPais(id_streamer)
    UNIQUE (nro_plataforma, nome)

Patrocinio(nro_empresa, id_canal, valor)
    nro_empresa referencia Empresa(nro)
    id_canal    referencia Canal(id_canal)

NivelCanal(id_canal, nivel, nome, valor, gif)
    id_canal referencia Canal(id_canal)
    UNIQUE (id_canal, nome)

Inscricao(id_canal, id_membro, nivel)
    (id_canal, nivel) referencia NivelCanal(id_canal, nivel)
    id_membro         referencia Usuario(id_usuario)

Video(id_video, id_canal, titulo, dataH, tema, duracao, visu_simul, visu_total)
    id_canal referencia Canal(id_canal)
    UNIQUE (id_canal, dataH, titulo)

Participa(id_video, id_streamer)
    id_video    referencia Video(id_video)
    id_streamer referencia StreamerPais(id_streamer)

Comentario(id_video, seq, id_usuario, texto, dataH, coment_on)
    id_video   referencia Video(id_video)
    id_usuario referencia Usuario(id_usuario)

Doacao(id_doacao, id_video, seq_comentario, seq_doacao, valor, status)
    (id_video, seq_comentario) referencia Comentario(id_video, seq)
    UNIQUE (id_video, seq_comentario, seq_doacao)

BitCoin(id_doacao, TxID)
    id_doacao referencia Doacao(id_doacao)
    UNIQUE (TxID)

PayPal(id_doacao, IdPayPal)
    id_doacao referencia Doacao(id_doacao)
    UNIQUE (IdPayPal)

CartaoCredito(id_doacao, nro, bandeira, dataH)
    id_doacao referencia Doacao(id_doacao)

MecanismoPlat(id_doacao, seq_plataforma)
    id_doacao referencia Doacao(id_doacao)
```

## Chaves primárias

| Relação | Chave primária |
|---|---|
| Conversao | moeda |
| Pais | DDI |
| Empresa | nro |
| Plataforma | nro |
| Usuario | id_usuario |
| PlataformaUsuario | (nro_plataforma, id_usuario) |
| StreamerPais | id_streamer |
| Canal | id_canal |
| Patrocinio | (nro_empresa, id_canal) |
| NivelCanal | (id_canal, nivel) |
| Inscricao | (id_canal, id_membro) |
| Video | id_video |
| Participa | (id_video, id_streamer) |
| Comentario | (id_video, seq) |
| Doacao | id_doacao |
| BitCoin / PayPal / CartaoCredito / MecanismoPlat | id_doacao |

## Moedas

| Valor | Moeda de armazenamento |
|---|---|
| `Patrocinio.valor` | Dólares americanos (definido pelo enunciado) |
| `Doacao.valor` | Moeda do país de residência do doador |
| `NivelCanal.valor` | Moeda do país de residência do dono do canal |

A conversão para dólares é sempre `valor * Conversao.fator_conver` da moeda correspondente, e é aplicada dentro das visões, nunca nas tabelas-base.
