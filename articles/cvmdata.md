# Introduction to cvmdata

## What `cvmdata` does

`cvmdata` provides a tidy R API to the open data published by the
Brazilian Securities and Exchange Commission — *Comissão de Valores
Mobiliários* (CVM). It fetches official CSV releases from the CVM portal
at <https://dados.cvm.gov.br/>, parses them respecting the upstream
encoding (`ISO-8859-1`) and the published field conventions, and returns
tibbles whose **table names, column names and categorical values are
preserved in Portuguese** exactly as published by CVM. Function names,
arguments and metadata attributes are in English, following the rOpenSci
and tidyverse conventions.

The package’s first release covers four core publicly-traded-company
datasets:

| Dataset id | Coverage |
|----|----|
| `cad` | Company registry (`Cadastro de Companhias Abertas`). |
| `itr` | Quarterly financial statements (`Informações Trimestrais`). |
| `dfp` | Annual financial statements (`Demonstrações Financeiras Padronizadas`). |
| `fre` | Reference form, including ESG/governance tables (`Formulário de Referência`). |

``` r

library(cvmdata)
cvm_datasets()
#> [1] "cad" "dfp" "fre" "itr"
```

## First call — the company registry

The simplest entry point is
[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md),
a thin alias for `cvm_fetch("cad", "companhias")`. It returns the
current snapshot of the open-company registry. The chunk below loads a
small slice of a real call pre-computed for this vignette (the package
itself hits the CVM portal on every invocation):

``` r

companies <- readRDS(system.file(
  "extdata", "vignette-data", "cad_companhias_sample.rds",
  package = "cvmdata"
))
companies
#> ℹ source: "cvm" | fetched_at: 2026-05-23 13:06:15.690987
#> ℹ dataset: "cad" | table: "companhias"
#>              cnpj_cia                                         denom_social
#> 1  08.773.135/0001-00            2W ECOBANK S.A. - EM RECUPERAÇÃO JUDICIAL
#> 2  11.396.633/0001-87                          3A COMPANHIA SECURITIZADORA
#> 3  01.547.749/0001-16 521 PARTICIPAÇOES S.A. - EM LIQUIDAÇÃO EXTRAJUDICIAL
#> 4  01.851.771/0001-55                                 524 PARTICIPAÇOES SA
#> 5  01.919.008/0001-19                                 525 PARTICIPAÇOES SA
#> 6  92.659.614/0001-06                           A J RENNER SA IND E PARTIP
#> 7  02.288.752/0001-25                                A.P. PARTICIPAÇOES SA
#> 8  21.649.280/0001-33                           ABC DADOS E INFORMATICA SA
#> 9  02.258.274/0001-00                                 ABC SUPERMERCADOS SA
#> 10 42.275.727/0001-21                          ABC XTAL MICROELETRONICA SA
#> 11 34.033.779/0001-63                   ABN AMRO ARRENDAMENTO MERCANTIL SA
#> 12 44.597.052/0001-62                                             ABRIL SA
#> 13 07.794.351/0001-60                  ABYARA PLANEJAMENTO IMOBILIÁRIO S/A
#> 14 07.636.657/0001-99                              ACO VERDE DO BRASIL S.A
#> 15 18.451.005/0001-04                       ACOPALMA CIA INDL ACOS V PALMA
#>                          denom_comerc     dt_reg   dt_const  dt_cancel
#> 1                     2W ECOBANK S.A. 2020-10-29 2007-03-23       <NA>
#> 2  TRIPLO A  COMPANHIA SECURITIZADORA 2010-03-08 2009-11-03 2015-12-18
#> 3               521 PARTICIPAÇÕES S/A 1997-07-11 1996-07-30       <NA>
#> 4                524 PARTICIPACOES SA 1997-05-30 1997-04-02       <NA>
#> 5                525 PARTICIPACOES SA 1997-07-16 1997-04-02 2006-05-30
#> 6                          A J RENNER 1969-06-24       <NA> 1998-06-17
#> 7             A.P. PARTICIPAÇÕES S.A. 1998-01-21 1997-12-14 2004-12-23
#> 8                    ABC COMPUTADORES 1988-06-03       <NA> 1993-03-05
#> 9                   ABC SUPERMERCADOS 1998-02-27 1997-09-30 2001-12-17
#> 10                               XTAL 1986-09-15       <NA> 1997-09-11
#> 11                     AYMORÉ LEASING 1995-12-20 1970-01-06 2009-09-30
#> 12                           ABRIL SA 1994-05-06       <NA> 1999-12-21
#> 13                             ABYARA 2006-07-24 2006-01-04 2010-05-28
#> 14            AÃO VERDE DO BRASIL S.A 2021-11-29 1985-05-07       <NA>
#> 15     ACOPALMA CIA INDL ACOS V PALMA 1978-05-09 1973-03-15 2007-08-07
#>                                       motivo_cancel                       sit
#> 1                                              <NA> SUSPENSO(A) - DECISÃO ADM
#> 2                           CANCELAMENTO VOLUNTÁRIO                 CANCELADA
#> 3                                              <NA>                     ATIVO
#> 4                                              <NA>                     ATIVO
#> 5                           ELISÃO POR INCORPORAÇÃO                 CANCELADA
#> 6          ATENDIMENTO AS NORMAS DA INSTR CVM 03/78                 CANCELADA
#> 7  ATENDIMENTO AS NORMAS DA INSTRUÇÃO CVM Nº 361/02                 CANCELADA
#> 8        ENQUADRAMENTO EXCEÇÕES DA INSTR. CVM 03/78                 CANCELADA
#> 9         ATENDIMENTO AS NORMAS DA INSTR CVM 229/95                 CANCELADA
#> 10         ATENDIMENTO AS NORMAS DA INSTR CVM 03/78                 CANCELADA
#> 11                          ELISÃO POR INCORPORAÇÃO                 CANCELADA
#> 12        ATENDIMENTO AS NORMAS DA INSTR CVM 229/95                 CANCELADA
#> 13                          CANCELAMENTO VOLUNTÁRIO                 CANCELADA
#> 14                                             <NA>                     ATIVO
#> 15  CANCELAMENTO DE OFÍCIO C/BASE INSTR. CVM 287/98                 CANCELADA
#>    dt_ini_sit cd_cvm                                              setor_ativ
#> 1  2026-05-19  25224                                        Energia Elétrica
#> 2  2015-12-18  21954                             Securitização de Recebíveis
#> 3  1997-07-11  16330                      Emp. Adm. Part. - Energia Elétrica
#> 4  1997-05-30  16284                   Emp. Adm. Part. - Sem Setor Principal
#> 5  2006-05-30  16349                   Emp. Adm. Part. - Sem Setor Principal
#> 6  1998-06-17     35                                 Emp. Adm. Participações
#> 7  2004-12-23  16802                                 Emp. Adm. Participações
#> 8  1993-03-05  13307                Máquinas, Equipamentos, Veículos e Peças
#> 9  2001-12-17  16934                             Comércio (Atacado e Varejo)
#> 10 1997-09-11  13005                Máquinas, Equipamentos, Veículos e Peças
#> 11 2009-09-30  15270                                  Arrendamento Mercantil
#> 12 1999-12-21  14370                                     Gráficas e Editoras
#> 13 2010-05-28  20206 Emp. Adm. Part. - Const. Civil, Mat. Const. e Decoração
#> 14 2021-11-29  26425                                 Metalurgia e Siderurgia
#> 15 2007-08-07     60                                 Metalurgia e Siderurgia
#>              tp_merc   categ_reg dt_ini_categ
#> 1               <NA> Categoria A   2020-10-29
#> 2               <NA> Categoria B   2010-03-08
#> 3               <NA> Categoria B   2011-04-28
#> 4              BOLSA Categoria A   2010-01-01
#> 5               <NA>        <NA>         <NA>
#> 6               <NA>        <NA>         <NA>
#> 7               <NA>        <NA>         <NA>
#> 8               <NA>        <NA>         <NA>
#> 9               <NA>        <NA>         <NA>
#> 10              <NA>        <NA>         <NA>
#> 11              <NA> Categoria A   2010-01-01
#> 12              <NA>        <NA>         <NA>
#> 13              <NA> Categoria A   2010-01-01
#> 14 BALCÃO ORGANIZADO Categoria B   2021-11-29
#> 15              <NA>        <NA>         <NA>
#>                               sit_emissor dt_ini_sit_emissor controle_acionario
#> 1  EM RECUPERAÇÃO JUDICIAL OU EQUIVALENTE         2025-04-23            PRIVADO
#> 2                    FASE PRÉ-OPERACIONAL         2010-03-08            PRIVADO
#> 3                LIQUIDAÇÃO EXTRAJUDICIAL         2015-04-30            PRIVADO
#> 4                        FASE OPERACIONAL         1997-05-30            PRIVADO
#> 5                                    <NA>               <NA>    PRIVADO HOLDING
#> 6                                    <NA>               <NA>            PRIVADO
#> 7                                    <NA>               <NA>            ESTATAL
#> 8                                    <NA>               <NA>            PRIVADO
#> 9                                    <NA>               <NA>            PRIVADO
#> 10                                   <NA>               <NA>            PRIVADO
#> 11                                   <NA>               <NA>            PRIVADO
#> 12                                   <NA>               <NA>            PRIVADO
#> 13                                   <NA>               <NA>            PRIVADO
#> 14                       FASE OPERACIONAL         2021-08-17            PRIVADO
#> 15                                   <NA>               <NA>            PRIVADO
#>    tp_ender                           logradouro                compl
#> 1      SEDE      Avenida Dr. Chucri Zaidan, 1550  8 and-conj 815-sl 1
#> 2      SEDE        Avenida Erasmo Braga, nº. 299             sala 703
#> 3      SEDE                     Av. Ayrton Senna     3000 - sala 4098
#> 4      SEDE Av. Presidente Antônio Carlos, nº 51      10º andar (pte)
#> 5      SEDE                     RUA LAURO MULLER       116, SALA 2201
#> 6      SEDE               R FREDERICO MENTZ 1606                 <NA>
#> 7      SEDE       AV. PRESIDENTE WILSON, 231 - 2             7º ANDAR
#> 8      SEDE               RUA FLORIDA 1670 12AND                 <NA>
#> 9      SEDE           RUA PAULO BARBOSA, 161/201                 <NA>
#> 10     SEDE                      AV BRASIL 20201                 <NA>
#> 11     SEDE       ALAMEDA ARAGUAIA, 731 PAV.SUP.              PARTE A
#> 12     SEDE       AV OTAVIANO ALVES DE LIMA 7221                 <NA>
#> 13     SEDE                   AVENIDA IBIRAPUERA   2332/T. 1/ 11ANDAR
#> 14     SEDE              Rodovia BR 222, Km 14,5 Gleba Itinga,Lote 71
#> 15     SEDE         ALAMEDA LOURIVAL BOECHAT 550                 <NA>
#>                  bairro             mun uf   pais      cep ddd_tel      tel
#> 1  Chacara Santo Antoni       SÃO PAULO SP BRASIL  4711130      11 39579400
#> 2                Centro  RIO DE JANEIRO RJ BRASIL 20020000      21 22338867
#> 3       Barra da Tijuca  RIO DE JANEIRO RJ BRASIL 22775003      21 25560809
#> 4                Centro  RIO DE JANEIRO RJ BRASIL 20020010      21 38043700
#> 5              BOTAFOGO  RIO DE JANEIRO RJ BRASIL 22290160      21 21967200
#> 6                  <NA>    PORTO ALEGRE RS BRASIL 90240111      51  3372033
#> 7                CENTRO  RIO DE JANEIRO RJ BRASIL 20030021      21 22208866
#> 8                  <NA>       SÃO PAULO SP BRASIL  4565000      11  5427188
#> 9                CENTRO      PETRÓPOLIS RJ BRASIL 25635000      24  2331415
#> 10                 <NA>  RIO DE JANEIRO RJ BRASIL 21515000      21 33726363
#> 11           ALPHAVILLE         BARUERI SP BRASIL  6455000      11 31746507
#> 12            PINHEIROS       SÃO PAULO SP BRASIL  5425902      11 30372010
#> 13           IBIRAPUERA       SÃO PAULO SP BRASIL  4028002      11 32960202
#> 14   Distrito de Pequiá      AÇAILÂNDIA MA BRASIL 65930000      99  5355122
#> 15           N.S.FATIMA VÁRZEA DA PALMA MG BRASIL 39250000      31 33352590
#>    ddd_fax      fax                       email
#> 1       11 39579499         ri@2wecobank.com.br
#> 2       21 22338867            dri@3asec.com.br
#> 3       21 25560809    eximia@eximiacapital.com
#> 4       21 38043480      gar@opportunity.com.br
#> 5       21 21967201                        <NA>
#> 6       51  3423595                        <NA>
#> 7       21 25333830  contabilidade3@acal.com.br
#> 8     <NA>       NA                        <NA>
#> 9       24  2311222        mfranca@abcsa.com.br
#> 10      21 33726950                        <NA>
#> 11      11 31746257 rubens.rossi@br.abnamro.com
#> 12      11 30372040       jaugusto@abril.com.br
#> 13    <NA>       NA            ri@abyara.com.br
#> 14      99  5355139         ri@ferroeste.com.br
#> 15      31 33442596                        <NA>
#>                                 tp_resp                                resp
#> 1  DIRETOR DE RELAÇÕES COM INVESTIDORES              FERNANDO GUEDES VIEIRA
#> 2  DIRETOR DE RELAÇÕES COM INVESTIDORES           FELIPE MARQUES DA FONSECA
#> 3                                  <NA>                                <NA>
#> 4  DIRETOR DE RELAÇÕES COM INVESTIDORES Maria Amalia Delfim de Melo Coutrim
#> 5  DIRETOR DE RELAÇÕES COM INVESTIDORES                 KEVIN MICHAEL ALTIT
#> 6  DIRETOR DE RELAÇÕES COM INVESTIDORES                  VERNER EGON RENNER
#> 7  DIRETOR DE RELAÇÕES COM INVESTIDORES            GILBERTO AUDELINO CORREA
#> 8  DIRETOR DE RELAÇÕES COM INVESTIDORES          JOSE GABRIEL CORREIA DAVID
#> 9  DIRETOR DE RELAÇÕES COM INVESTIDORES              MARCELO FRANÇA DE LIMA
#> 10 DIRETOR DE RELAÇÕES COM INVESTIDORES      WALTER EDUARDO TEIXEIRA MACHAD
#> 11 DIRETOR DE RELAÇÕES COM INVESTIDORES          CARLOS ALBERTO LÓPEZ GALÁN
#> 12 DIRETOR DE RELAÇÕES COM INVESTIDORES          JOSE AUGUSTO PINTO MOREIRA
#> 13 DIRETOR DE RELAÇÕES COM INVESTIDORES                   MARCOS YUITI MORI
#> 14 DIRETOR DE RELAÇÕES COM INVESTIDORES           Gustavo Rozenbaum Bcheche
#> 15 DIRETOR DE RELAÇÕES COM INVESTIDORES      MILTON ALENCAR ASSIS DE TOLEDO
#>    dt_ini_resp               logradouro_resp        compl_resp
#> 1   2026-04-22    AV DR. CHUCRI ZAIDAN, 1550 8 AND-CONJ815-SL1
#> 2   2011-06-16 AVENIDA ERASMO BRAGA, Nº. 299          SALA 703
#> 3         <NA>                          <NA>              <NA>
#> 4   2026-05-06 Av. Presidente Antônio Carlos                51
#> 5   2005-06-14          RUA LAURO MULLER 116      2201 (PARTE)
#> 6   1969-06-24     RUA FREDERICO MENTZ, 1606              <NA>
#> 7   2004-10-11                     RUA CEARá          1305/802
#> 8   1988-06-03        RUA FLORIDA 1670 12AND              <NA>
#> 9   1998-02-27               RUA TEREZA 1415              <NA>
#> 10  1986-09-15               AV BRASIL 20201              <NA>
#> 11  2009-08-12              AVENIDA PAULISTA              1374
#> 12  1994-05-06 AV NAÇÕES UNIDAS, 7221/2º AND              <NA>
#> 13  2009-06-08   RUA GOMES DE CARVALHO, 1510          6º ANDAR
#> 14  2021-08-09      Avenida do Contorno 3800         19º andar
#> 15  1978-05-09         RUA ALVES DO VALE, 14              <NA>
#>             bairro_resp       mun_resp uf_resp pais_resp cep_resp ddd_tel_resp
#> 1  CHÁCARA STO. ANTÔNIO      SÃO PAULO      SP      <NA>  4711130           11
#> 2                CENTRO RIO DE JANEIRO      RJ      <NA> 20020000           21
#> 3                  <NA>           <NA>    <NA>      <NA>       NA         <NA>
#> 4                Centro RIO DE JANEIRO      RJ      <NA> 20020010           21
#> 5              BOTAFOGO RIO DE JANEIRO      RJ      <NA> 22290160           21
#> 6                  <NA>   PORTO ALEGRE      RS      <NA> 90000000           51
#> 7          FUNCIONáRIOS BELO HORIZONTE      MG      <NA> 30150311           31
#> 8                  <NA>      SÃO PAULO      SP      <NA> 21510000           21
#> 9         ALTO DA SERRA     PETRÓPOLIS      RJ      <NA> 25635000           24
#> 10                 <NA> RIO DE JANEIRO      RJ      <NA> 21510000           21
#> 11           BELA VISTA      SÃO PAULO      SP      <NA>  1310916           11
#> 12            PINHEIROS      SÃO PAULO      SP      <NA>  5425902           11
#> 13         VILA OLÍMPIA      SÃO PAULO      SP      <NA>  4547005           11
#> 14       Santa Efigênia BELO HORIZONTE      MG      <NA> 30110022           31
#> 15        CORAçAO JESUS BELO HORIZONTE      MG      <NA> 30380320           31
#>    tel_resp ddd_fax_resp fax_resp                 email_resp       cnpj_auditor
#> 1  39579400         <NA>       NA  juridico@2wecobank.com.br 10.830.108/0001-65
#> 2  22338867           21 22338867 juridico@triploasec.com.br 60.525.706/0001-07
#> 3      <NA>         <NA>       NA                       <NA> 02.878.522/0001-16
#> 4  38043700         <NA>       NA     gar@opportunity.com.br 10.830.108/0001-65
#> 5  21967200           21 21967201   kevin@mattosfilho.com.br 11.245.719/0001-09
#> 6   3142033         0051  3743595                       <NA> 44.038.248/0001-17
#> 7  32354268           31 32737218    gilberto@acesita.com.br 02.248.211/0001-73
#> 8   5427188         0021       NA                       <NA> 33.017.310/0001-78
#> 9   2331415           24  2311231       mfranca@abcsa.com.br 33.017.310/0001-78
#> 10 33726363         0021       NA                       <NA> 61.562.112/0001-20
#> 11 31749611           11 31746751    cgalan@santander.com.br 49.928.567/0001-11
#> 12 30372010           11 30372040      jaugusto@abril.com.br 33.017.310/0001-78
#> 13 32960202           11 32960201           ri@abyara.com.br 00.326.016/0001-99
#> 14 32282500         <NA>       NA        ri@ferroeste.com.br 61.562.112/0001-20
#> 15 33352590           31 33442596       maatoledo@uol.com.br 61.411.393/0001-10
#>                                                   auditor
#> 1            GRANT THORNTON AUDITORES INDEPENDENTES LTDA.
#> 2    MOORE STEPHENS LIMA LUCCHESI AUDITORES INDEPENDENTES
#> 3            IRKO HIRASHIMA AUDITORES INDEPENDENTES LTDA.
#> 4            GRANT THORNTON AUDITORES INDEPENDENTES LTDA.
#> 5                                       DIRECTA AUDITORES
#> 6                          ARTHUR ANDERSEN BIEDERMANN A I
#> 7                            CANARIM AUDITORES ASSOCIADOS
#> 8                                              RUHTRA S/C
#> 9                                              RUHTRA S/C
#> 10   PRICEWATERHOUSECOOPERS AUDITORES INDEPENDENTES LTDA.
#> 11 DELOITTE TOUCHE TOHMATSU AUDITORES INDEPENDENTES LTDA.
#> 12                                             RUHTRA S/C
#> 13      TERCO AUDITORES INDEPENDENTES - SOCIEDADE SIMPLES
#> 14   PRICEWATERHOUSECOOPERS AUDITORES INDEPENDENTES LTDA.
#> 15                   WALTER HEUER AUDITORES INDEPENDENTES
```

Every tibble returned by a `cvmdata` fetcher carries five provenance
attributes:

``` r

attr(companies, "source")
#> [1] "cvm"
attr(companies, "dataset")
#> [1] "cad"
attr(companies, "table")
#> [1] "companhias"
attr(companies, "package_version")
#> [1] "0.0.0.9000"
# `fetched_at` is a POSIXct timestamp set at download time.
```

These attributes survive subsetting via standard tibble operations and
are displayed at the top of the print output, so the dataset’s origin
and freshness travel with the data.

## The general API — `cvm_fetch()`

[`cad_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cad_fetch.md)
is convenience. The single entry point for every dataset and every table
is `cvm_fetch(dataset, table, ...)`. The example below shows what eight
rows of BCO BRASIL’s individual balance sheet look like for 2024 — also
pre-computed:

``` r

bb_bpa <- readRDS(system.file(
  "extdata", "vignette-data", "dfp_bpa_bb_2024_sample.rds",
  package = "cvmdata"
))
bb_bpa
#> ℹ source: "cvm" | fetched_at: 2026-05-23 13:06:16.55788
#> ℹ dataset: "dfp" | table: "bpa"
#>             cnpj_cia   dt_refer versao       denom_cia cd_cvm
#> 1 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 2 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 3 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 4 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 5 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 6 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 7 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#> 8 00.000.000/0001-91 2024-12-31      1 BCO BRASIL S.A. 001023
#>                                   grupo_dfp moeda ordem_exerc dt_fim_exerc
#> 1 DF Individual - Balanço Patrimonial Ativo  REAL   PENÚLTIMO   2023-12-31
#> 2 DF Individual - Balanço Patrimonial Ativo  REAL      ÚLTIMO   2024-12-31
#> 3 DF Individual - Balanço Patrimonial Ativo  REAL   PENÚLTIMO   2023-12-31
#> 4 DF Individual - Balanço Patrimonial Ativo  REAL      ÚLTIMO   2024-12-31
#> 5 DF Individual - Balanço Patrimonial Ativo  REAL   PENÚLTIMO   2023-12-31
#> 6 DF Individual - Balanço Patrimonial Ativo  REAL      ÚLTIMO   2024-12-31
#> 7 DF Individual - Balanço Patrimonial Ativo  REAL   PENÚLTIMO   2023-12-31
#> 8 DF Individual - Balanço Patrimonial Ativo  REAL      ÚLTIMO   2024-12-31
#>   cd_conta                      ds_conta     vl_conta st_conta_fixa
#> 1        1                   Ativo Total 2.208054e+12             S
#> 2        1                   Ativo Total 2.395432e+12             S
#> 3     1.01 Caixa e Equivalentes de Caixa 6.017770e+10             S
#> 4     1.01 Caixa e Equivalentes de Caixa 8.115033e+10             S
#> 5  1.01.01                         Caixa 1.402270e+10             S
#> 6  1.01.01                         Caixa 1.718812e+10             S
#> 7  1.01.02        Aplicações de Liquidez 4.615499e+10             S
#> 8  1.01.02        Aplicações de Liquidez 6.396220e+10             S
```

Two things are worth noting on the output:

- `vl_conta` (account amount) is already in absolute Brazilian reais.
  CVM publishes a separate `ESCALA_MOEDA` field (`UNIDADE`, `MIL`,
  `MILHÃO`, `BILHÃO`);
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
  multiplies `VL_CONTA` by the scale and drops the scale column. The
  “known defects” article walks through this transformation explicitly.
- `dt_refer`, `dt_fim_exerc` and other dates arrive as proper R `Date`,
  even though CVM ships them as `YYYY-MM-DD` strings. The conversion is
  driven by the published dictionary (`tipo_dados = "date"`).

## Selecting companies

The `companies` argument accepts CNPJ (with or without punctuation),
CD_CVM (with or without zero-padding), or a free-text search against
`denom_cia`. Detection is automatic per element. In non-interactive
sessions, ambiguous text matches abort with a list of candidates so
batch scripts never silently take the wrong issuer.

``` r

# Three equivalent forms for one issuer:
cvm_fetch("dfp", "bpa", report_type = "ind",
          companies = "1023",                 years = 2024)
cvm_fetch("dfp", "bpa", report_type = "ind",
          companies = "00.000.000/0001-91",   years = 2024)
cvm_fetch("dfp", "bpa", report_type = "ind",
          companies = "BCO BRASIL S.A.",      years = 2024) # exact
```

The `cvm-fetch` article goes through CNPJ vs. CD_CVM vs. text in depth,
including the CD_CVM-to-CNPJ lookup performed automatically for tables
that lack a `cd_cvm` column (e.g. `composicao_capital`).

## Discovery

Two helpers describe what the package knows without touching the
network:

``` r

cvm_tables("dfp")
#>  [1] "bpa"                "bpp"                "composicao_capital"
#>  [4] "dfc_md"             "dfc_mi"             "dmpl"              
#>  [7] "dra"                "dre"                "dva"               
#> [10] "parecer"            "submissao"

# Dictionary for the columns of dfp/bpa, sourced from the published
# CVM META resources at snapshot time.
head(cvm_dictionary("dfp", "bpa"), 5)
#> # A tibble: 5 × 8
#>   campo     campo_original descricao   dominio tipo_dados tamanho precisao scale
#>   <chr>     <chr>          <chr>       <chr>   <chr>        <int>    <int> <int>
#> 1 cd_conta  CD_CONTA       Código da … Numéri… varchar         18       NA    NA
#> 2 cd_cvm    CD_CVM         Código CVM  Numéri… char             6       NA    NA
#> 3 cnpj_cia  CNPJ_CIA       CNPJ da co… Alfanu… varchar         20       NA    NA
#> 4 denom_cia DENOM_CIA      Nome empre… Alfanu… varchar        100       NA    NA
#> 5 ds_conta  DS_CONTA       Descrição … Alfanu… varchar        100       NA    NA
```

`cvm_codelist(dataset, table, column)` returns the enumerated values of
categorical columns (e.g. `sit` in `cad/companhias` —
`ATIVO`/`CONCEDIDO REGISTRO`/etc.); `cvm_dataset_years(dataset)`
discovers the years available upstream for a yearly-partitioned dataset.

## Cache, source backend, and where to read next

[`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md)
caches downloaded artefacts under
`tools::R_user_dir("cvmdata", "cache")` with HTTP revalidation gated by
a 30-day TTL. Cached units are LRU-evicted once the cache exceeds the
configurable size limit (`cvmdata.cache_max_size_mb`, default 100 MiB).
[`cvm_cache_info()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_info.md)
reports current size and unit breakdown;
[`cvm_cache_clear()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_cache_clear.md)
resets it.

The `source` argument selects the backend. From v0.1.0 the default is
`"mirror"`: a parquet snapshot in GitHub Releases consulted via DuckDB
with year-partition filter pushdown, refreshed weekly by an ETL workflow
in this repo. The `"cvm"` backend (direct HTTP to the open-data portal)
remains fully supported and is selected per call or persisted via
`cvm_source_set("cvm")`.

Further reading on the pkgdown site:

- **cvm-fetch** — deep dive on
  [`cvm_fetch()`](https://sidneybissoli.github.io/cvmdata/reference/cvm_fetch.md),
  including `companies`/`years`/`report_type`/`on_error`/`validate`
  semantics.
- **itr-dfp** — quarterly and annual financial statements, with two
  end-to-end workflows.
- **fre** — reference form, including the eight ESG/governance tables
  that ship without CVM-published META.
- **cvm-defects** — known quirks of the CVM publication and how
  `cvmdata` handles each one.
