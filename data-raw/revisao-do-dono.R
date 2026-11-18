# Revisão do dono — cvmdata 0.3.1, de ponta a ponta
#
# Para quê: antes de enviar à rOpenSci, usar o pacote como um usuário usa e
# ver se ele faz o que você quer. Este roteiro não substitui os testes
# automáticos; ele é a SUA conferência.
#
# Como usar (RStudio ou Positron):
#   1. Abra este arquivo.
#   2. Rode UM bloco por vez (selecione o bloco e Ctrl+Enter). Cada bloco
#      começa com `passo(...)`.
#   3. Em cada bloco há dois tipos de conferência:
#        confere(...)  -> o roteiro confere sozinho e imprime [ok] ou [FALHOU]
#        olhe(...)     -> só você pode julgar: leia o resultado e decida
#   4. No fim, `placar()` mostra quantas conferências automáticas passaram.
#      O que foi marcado com olhe() você anota à mão.
#
# Precisa de internet. A primeira leitura de cada conjunto baixa arquivos;
# o roteiro inteiro leva de 10 a 20 minutos.
#
# Nada aqui altera o espelho, o repositório ou o Zenodo. O bloco 11 limpa o
# cache local do pacote nesta máquina, que se refaz sozinho.

# ---- 0. Preparação ----------------------------------------------------

# Instala do GitHub, como um usuário instalaria, e não da pasta de
# desenvolvimento. Rode uma vez; depois pode pular.
# A v0.3.1 não tem cvm_arguments() (bloco 3b) nem cnpj_lookup() (bloco
# 7b); para testá-las, instale o main (0.3.1.9000):
# pak::pak("SidneyBissoli/cvmdata")

library(cvmdata)
library(tidyverse)

.revisao <- new.env()
.revisao$ok <- 0L
.revisao$falhou <- character()
.revisao$olhar <- character()

passo <- function(titulo) {
  cat(
    "\n",
    strrep("=", 70),
    "\n",
    titulo,
    "\n",
    strrep("=", 70),
    "\n",
    sep = ""
  )
}
confere <- function(descricao, condicao) {
  passou <- isTRUE(tryCatch(condicao, error = function(e) FALSE))
  if (passou) {
    .revisao$ok <- .revisao$ok + 1L
    cat("  [ok]      ", descricao, "\n", sep = "")
  } else {
    .revisao$falhou <- c(.revisao$falhou, descricao)
    cat("  [FALHOU]  ", descricao, "\n", sep = "")
  }
  invisible(passou)
}
olhe <- function(texto) {
  .revisao$olhar <- c(.revisao$olhar, texto)
  cat("  [OLHE]    ", texto, "\n", sep = "")
}
# Roda uma chamada que DEVE dar erro e devolve o erro (ou NULL se não deu).
erro_de <- function(expr) {
  tryCatch(
    {
      force(expr)
      NULL
    },
    error = function(e) e
  )
}
placar <- function() {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat("Conferências automáticas que passaram:", .revisao$ok, "\n")
  cat("Conferências automáticas que falharam:", length(.revisao$falhou), "\n")
  for (f in .revisao$falhou) {
    cat("   -", f, "\n")
  }
  cat("Pontos para o seu julgamento:", length(.revisao$olhar), "\n")
}

petr <- "33.000.167/0001-01" # Petrobras
bb <- "00.000.000/0001-91" # Banco do Brasil

passo("0. Versão instalada")
print(packageVersion("cvmdata"))
confere(
  "a versão instalada é a 0.3.1 ou posterior",
  packageVersion("cvmdata") >= "0.3.1"
)
confere(
  "a versão instalada tem cvm_arguments() (senão o bloco 3b falha)",
  exists("cvm_arguments", envir = asNamespace("cvmdata"))
)
confere(
  "a versão instalada tem cnpj_lookup() (senão o bloco 7b falha)",
  exists("cnpj_lookup", envir = asNamespace("cvmdata"))
)
confere("a fonte padrão é o espelho", identical(cvm_source_get(), "mirror"))
confere("nenhuma data fixada", identical(cvm_release_get(), "latest"))

# ---- 1. Descobrir o que existe ----------------------------------------

passo("1. Descoberta: o que o pacote cobre")
print(cvm_datasets())
confere("são nove conjuntos", length(cvm_datasets()) == 9L)
n_tabelas <- sum(vapply(cvm_datasets(), function(d) length(cvm_tables(d)), 1L))
confere("são 104 tabelas no total", n_tabelas == 104L)
print(cvm_tables("dfp"))
dic <- cvm_dictionary("dfp", "dre")
print(dic)
confere(
  "o dicionário da DRE tem descrição para cada campo",
  all(nzchar(dic$descricao))
)
print(cvm_dataset_years("dfp"))
confere("a DFP começa em 2010", min(cvm_dataset_years("dfp")) == 2010L)
olhe(
  "Os nomes dos conjuntos e das tabelas fazem sentido para quem conhece a CVM?"
)
olhe("cvm_groups() lista os 18 grupos do portal; a tabela abaixo está legível?")
cvm_groups() |> arrange(desc(n_datasets)) |> print()

# ---- 2. A leitura mais comum -------------------------------------------

passo("2. DRE consolidada da Petrobras em 2024, pelo ticker")
dre <- cvm_fetch("dfp", "dre", ticker = "PETR4", year = 2024, basis = "con")
print(dre)
confere("veio uma tabela do pacote (cvm_tbl)", inherits(dre, "cvm_tbl"))
confere("veio do espelho", identical(attr(dre, "source"), "mirror"))
confere("só há uma companhia", length(unique(dre$cnpj_cia)) == 1L)
confere("a companhia é a Petrobras", unique(dre$cnpj_cia) == petr)
confere("a coluna escala_moeda foi removida", !"escala_moeda" %in% names(dre))
confere("a data de referência é uma data", inherits(dre$dt_refer, "Date"))
confere("o código CVM é texto", is.character(dre$cd_cvm))
receita <- dre[dre$cd_conta == "3.01" & dre$ordem_exerc == "ÚLTIMO", ]
print(receita[, c("ds_conta", "vl_conta", "dt_ini_exerc", "dt_fim_exerc")])
confere(
  "a receita está em reais (centenas de bilhões), não em milhares",
  receita$vl_conta[1] > 1e11
)
olhe("A receita líquida de 2024 acima bate com o que a Petrobras divulgou?")
olhe(
  "O cabeçalho impresso (fonte, data, conjunto, tabela) diz o que você quer saber?"
)

# ---- 3. Individual e consolidado ---------------------------------------

passo("3. O argumento basis: obrigatório, sem palpite")
e <- erro_de(cvm_fetch("dfp", "dre", cnpj = petr, year = 2024))
confere(
  "sem basis, a DRE dá erro de entrada",
  inherits(e, "cvmdata_error_input")
)
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}
olhe("A mensagem de erro acima explica o que fazer?")
duas <- cvm_fetch(
  "dfp",
  "dre",
  cnpj = petr,
  year = 2024,
  basis = c("ind", "con")
)
print(table(duas$basis))
confere(
  "com as duas bases, vêm as duas",
  setequal(unique(duas$basis), c("ind", "con"))
)
e <- erro_de(cvm_fetch("cad", "companhias", basis = "con"))
confere(
  "basis em tabela sem essa divisão dá erro",
  inherits(e, "cvmdata_error_input")
)

# ---- 3b. Que argumentos cada tabela aceita ----------------------------

passo("3b. cvm_arguments(): obrigatórios, opcionais e proibidos")
# Uma linha por argumento de cvm_fetch(): status ("required", "optional",
# "not allowed") e os valores aceitos. Não usa a internet.
regra <- function(t, arg) t$status[t$argument == arg]

dre_args <- cvm_arguments("dfp", "dre")
print(dre_args, n = Inf)
confere("na DRE, basis é obrigatório", regra(dre_args, "basis") == "required")
confere(
  "na DRE, reading é opcional",
  regra(dre_args, "reading") == "optional"
)
confere(
  "na DRE, as_of não se aplica",
  regra(dre_args, "as_of") == "not allowed"
)
confere("na DRE, year é opcional", regra(dre_args, "year") == "optional")

cad_args <- cvm_arguments("cad", "companhias")
print(cad_args, n = Inf)
confere(
  "no cadastro, basis e year não se aplicam",
  all(c(regra(cad_args, "basis"), regra(cad_args, "year")) == "not allowed")
)
confere("no cadastro, as_of é opcional", regra(cad_args, "as_of") == "optional")

# Tabela que a CVM parou de publicar em 2023: year passa a ser obrigatório.
leg_args <- cvm_arguments("fre", "endividamento")
print(leg_args[leg_args$argument == "year", ])
confere(
  "em tabela legada do FRE, year é obrigatório",
  regra(leg_args, "year") == "required"
)

# Tabela de pessoas: não está no espelho, e a coluna values diz isso.
pes_args <- cvm_arguments("fre", "responsavel")
print(pes_args[pes_args$argument == "source", ])
confere(
  "em tabela de pessoas, source avisa que ela não está no espelho",
  grepl("not in the mirror", pes_args$values[pes_args$argument == "source"])
)

# O que a função diz é o que cvm_fetch() faz: "not allowed" dá erro de
# entrada antes de baixar qualquer coisa.
e <- erro_de(cvm_fetch("cad", "companhias", year = 2024))
confere(
  "year em tabela sem ano dá erro de entrada (e cvm_arguments diz 'not allowed')",
  inherits(e, "cvmdata_error_input") &&
    regra(cad_args, "year") == "not allowed"
)
e <- erro_de(cvm_arguments("dfp", "nada"))
confere(
  "tabela inexistente dá erro de entrada",
  inherits(e, "cvmdata_error_input")
)
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}
olhe("A tabela da DRE acima responde à pergunta 'o que eu preciso passar?'")
olhe(
  "A coluna values diz o bastante (anos, formatos), ou falta algo que você procuraria?"
)
olhe(
  "Abra ?cvm_fetch, seção 'Arguments by table': ela aponta para cvm_arguments()?"
)

# ---- 4. Períodos --------------------------------------------------------

passo("4. Anos e janela de datas")
tres <- cvm_fetch("dfp", "dre", cnpj = petr, year = 2022:2024, basis = "con")
print(table(format(tres$dt_refer, "%Y")))
confere(
  "três anos pedidos, três anos devolvidos",
  length(unique(format(tres$dt_refer, "%Y"))) == 3L
)
janela <- cvm_fetch(
  "itr",
  "dre",
  cnpj  = petr,
  from  = "2024-04-01",
  to    = "2024-09-30",
  basis = "con"
)
print(sort(unique(janela$dt_refer)))
confere(
  "a janela de abril a setembro traz o 2º e o 3º trimestres",
  setequal(as.character(unique(janela$dt_refer)), c("2024-06-30", "2024-09-30"))
)
e <- erro_de(cvm_fetch(
  "itr",
  "dre",
  cnpj = petr,
  year = 2024,
  from = "2024-01-01",
  to = "2024-06-30",
  basis = "con"
))
confere("year junto com from/to dá erro", inherits(e, "cvmdata_error_input"))
# Sem ano: o pacote lê o arquivo mais recente e, se a companhia não está
# nele, recua um ano (até três), avisando. Igual pelas duas fontes.
recuo <- NULL
sem_ano <- withCallingHandlers(
  cvm_fetch("dfp", "dre", cnpj = petr, basis = "con"),
  cvmdata_warn_year_fallback = function(w) {
    recuo <<- w
    invokeRestart("muffleWarning")
  }
)
if (!is.null(recuo)) {
  cat(conditionMessage(recuo), "\n")
}
confere(
  "sem ano, a Petrobras vem (do arquivo mais recente em que está)",
  nrow(sem_ano) > 0L
)
olhe("Se apareceu o aviso de recuo acima, ele explica por que o ano é outro?")
e <- erro_de(cvm_fetch("dfp", "dre", cnpj = petr, year = 2005, basis = "con"))
confere(
  "ano anterior ao primeiro publicado dá erro",
  inherits(e, "cvmdata_error_input")
)
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}

# ---- 5. Valor original e valor reexpresso ------------------------------

passo("5. reading: o exercício como foi publicado e como foi reapresentado")
bpa <- suppressMessages(cvm_fetch(
  "dfp",
  "bpa",
  cnpj    = bb,
  year    = 2024,
  basis   = "con",
  reading = c("original", "restated")
))
print(table(bpa$reading))
confere(
  "vêm as duas leituras",
  setequal(unique(bpa$reading), c("original", "restated"))
)
lado <- merge(
  bpa[bpa$reading == "original", c("cd_conta", "ds_conta", "vl_conta")],
  bpa[bpa$reading == "restated", c("cd_conta", "vl_conta")],
  by = "cd_conta",
  suffixes = c("_original", "_reexpresso")
)
mudou <- lado[lado$vl_conta_original != lado$vl_conta_reexpresso, ]
print(utils::head(mudou, 8))
cat(
  "contas do ativo de 2024 do Banco do Brasil que mudaram na reapresentação:",
  nrow(mudou),
  "\n"
)
olhe("Faz sentido para você ver as duas leituras lado a lado deste jeito?")

# ---- 6. Todas as versões de um documento -------------------------------

passo("6. cvm_versions(): entregas substituídas")
v <- suppressMessages(cvm_versions(
  "dfp",
  "dre",
  cnpj  = "42.150.391/0001-70",
  year  = 2023,
  basis = "con"
))
print(unique(v[, c(
  "versao",
  "superseded_at",
  "superseded_by_versao",
  "history_source",
  "scale_error"
)]))
confere("há mais de uma versão", length(unique(v$versao)) > 1L)
confere("a coluna scale_error existe", "scale_error" %in% names(v))
olhe(
  "Dá para entender, pela tabela, qual versão vale hoje e quando as outras caíram?"
)

# ---- 7. Cadastro e companhias que saíram da bolsa ----------------------

passo("7. Cadastro: registros em vigor numa data e ticker de deslistada")
hoje <- cvm_fetch("cad", "companhias")
em2015 <- cvm_fetch("cad", "companhias", as_of = "2015-12-31")
cat(
  "registros hoje:",
  nrow(hoje),
  "| registros em vigor em 31/12/2015:",
  nrow(em2015),
  "\n"
)
confere(
  "o retrato de 2015 é menor que o cadastro inteiro",
  nrow(em2015) < nrow(hoje)
)
confere(
  "todo registro de 2015 já existia naquela data",
  all(em2015$dt_reg <= as.Date("2015-12-31"))
)
confere(
  "o cadastro não traz o responsável nem contatos",
  !any(c("resp", "email", "tel", "email_resp") %in% names(hoje))
)
gol <- suppressMessages(cvm_fetch(
  "dfp",
  "dre",
  ticker = "GOLL4",
  year   = 2019,
  basis  = "con"
))
print(unique(gol$denom_cia))
confere("o ticker de uma deslistada (GOLL4) resolve", nrow(gol) > 0L)
e <- erro_de(cvm_fetch(
  "dfp",
  "dre",
  cnpj = "Petrobras",
  year = 2024,
  basis = "con"
))
confere("nome no lugar do CNPJ dá erro", inherits(e, "cvmdata_error_input"))
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}
olhe("A mensagem acima deixa claro que o pacote só aceita CNPJ ou ticker?")
olhe("Ela aponta para cnpj_lookup() como o caminho para achar o CNPJ?")

passo("7b. cnpj_lookup(): achar o CNPJ pelo nome")
# Procura nos três cadastros do cad (companhias, estrangeiras,
# incentivadas), na razão social e no nome comercial. Cada palavra precisa
# aparecer, em qualquer ordem, sem ligar para caixa e acento. Lista os
# candidatos e nunca escolhe.
pb <- cnpj_lookup("petroleo brasileiro")
print(pb)
confere("'petroleo brasileiro' acha a Petrobras", petr %in% pb$cnpj_cia)
confere(
  "o acento não muda o resultado ('petróleo' = 'petroleo')",
  setequal(cnpj_lookup("Petróleo Brasileiro")$cnpj_cia, pb$cnpj_cia)
)
confere(
  "a ordem das palavras não muda o resultado",
  setequal(cnpj_lookup("brasileiro petroleo")$cnpj_cia, pb$cnpj_cia)
)
confere(
  "as colunas são as prometidas no help",
  identical(
    names(pb),
    c(
      "cnpj_cia",
      "denom_social",
      "denom_comerc",
      "cd_cvm",
      "sit",
      "dt_reg",
      "dt_cancel",
      "table"
    )
  )
)

# Um nome curto devolve vários candidatos; as ativas vêm primeiro.
bancos <- cnpj_lookup("banco brasil")
print(bancos, n = 20)
confere(
  "nenhuma linha repetida (as repetições por mercado foram juntadas)",
  !anyDuplicated(bancos[, c("cnpj_cia", "cd_cvm", "table")])
)
confere(
  "as canceladas vêm depois das ativas",
  !is.unsorted(!is.na(bancos$dt_cancel))
)
confere("o Banco do Brasil está entre os candidatos", bb %in% bancos$cnpj_cia)

# O fluxo inteiro: achar o CNPJ, depois buscar com ele.
dre_pb <- suppressMessages(cvm_fetch(
  "dfp",
  "dre",
  cnpj = pb$cnpj_cia[1],
  year = 2024,
  basis = "con"
))
confere("o CNPJ achado serve em cvm_fetch()", nrow(dre_pb) > 0L)

nada <- cnpj_lookup("zzz companhia que nao existe")
confere("busca sem resultado devolve zero linhas, sem erro", nrow(nada) == 0L)
e <- erro_de(cnpj_lookup(c("petrobras", "vale")))
confere(
  "mais de um nome por chamada dá erro de entrada",
  inherits(e, "cvmdata_error_input")
)
olhe("Procure duas ou três companhias que você conhece: elas aparecem?")
olhe("A mensagem de busca sem resultado (acima) ajuda a tentar de novo?")
olhe(
  "Abra ?cnpj_lookup: fica claro que nomes antigos (ex.: BR Distribuidora) não são achados?"
)

# ---- 8. Formulário de Referência e dados pessoais ----------------------

passo("8. FRE: tabela de companhia, tabela de contagem e tabela de pessoas")
cap <- cvm_fetch("fre", "capital_social", cnpj = petr, year = 2025)
print(cap)
confere(
  "capital social vem do espelho",
  identical(attr(cap, "source"), "mirror")
)

aviso <- NULL
pcd <- withCallingHandlers(
  cvm_fetch("fre", "empregado_PCD", year = 2025),
  cvmdata_warn_privacy_omitted = function(w) {
    aviso <<- w
    invokeRestart("muffleWarning")
  }
)
if (!is.null(aviso)) {
  cat(conditionMessage(aviso), "\n")
}
confere("a tabela de contagem avisa das companhias omitidas", !is.null(aviso))
confere(
  "os números da omissão ficam no resultado",
  !is.null(attr(pcd, "omitted"))
)
print(attr(pcd, "omitted"))
olhe(
  "O aviso acima diz, em linguagem que o usuário entende, o que não veio e por quê?"
)

mensagem <- NULL
acion <- withCallingHandlers(
  cvm_fetch("fre", "posicao_acionaria", cnpj = bb, year = 2024),
  cvmdata_message_unmirrored = function(m) {
    mensagem <<- m
    invokeRestart("muffleMessage")
  }
)
if (!is.null(mensagem)) {
  cat(conditionMessage(mensagem), "\n")
}
confere(
  "a tabela de acionistas é lida direto da CVM",
  identical(attr(acion, "source"), "cvm")
)
olhe(
  "A mensagem de troca de fonte acima está clara? (ela aparece uma vez por sessão)"
)
e <- erro_de(cvm_fetch(
  "fre",
  "posicao_acionaria",
  cnpj = bb,
  year = 2024,
  source = "mirror"
))
confere(
  "pedir essa tabela ao espelho, de propósito, dá erro",
  inherits(e, "cvmdata_error_input")
)
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}

# ---- 9. Espelho contra a CVM -------------------------------------------

passo("9. O espelho devolve o mesmo que a CVM?")
do_espelho <- cvm_fetch("dfp", "dre", cnpj = petr, year = 2024, basis = "con")
da_cvm <- cvm_fetch(
  "dfp",
  "dre",
  cnpj = petr,
  year = 2024,
  basis = "con",
  source = "cvm"
)
confere(
  "mesmas colunas",
  identical(sort(names(do_espelho)), sort(names(da_cvm)))
)
confere("mesmo número de linhas", nrow(do_espelho) == nrow(da_cvm))
chave <- function(x) {
  x <- as.data.frame(x)[
    order(x$cd_conta, x$ordem_exerc),
    c("cd_conta", "ordem_exerc", "vl_conta")
  ]
  rownames(x) <- NULL
  x
}
confere(
  "mesmos valores, conta a conta",
  isTRUE(all.equal(chave(do_espelho), chave(da_cvm)))
)
cat(
  "fonte de cada um:",
  attr(do_espelho, "source"),
  "e",
  attr(da_cvm, "source"),
  "\n"
)
olhe(
  "Se a CVM publicou algo novo nesta semana, pode haver diferença; ela faria sentido?"
)

# ---- 10. Fixar o espelho numa data -------------------------------------

passo("10. Reprodutibilidade: fixar a data do espelho")
cvm_release_set("2026-11-15")
fixo <- cvm_fetch("dfp", "dre", cnpj = petr, year = 2024, basis = "con")
print(attr(fixo, "release"))
confere(
  "a leitura diz de que foto veio",
  grepl("snapshot-2026-11-15", attr(fixo, "release"), fixed = TRUE)
)
e <- erro_de(cvm_fetch("fre", "membro_comite", year = 2024))
confere(
  "com data fixada, tabela de pessoas dá erro em vez de trocar de fonte",
  inherits(e, "cvmdata_error_input")
)
if (!is.null(e)) {
  cat(conditionMessage(e), "\n")
}
cvm_release_set("latest")
confere("a data foi solta de novo", identical(cvm_release_get(), "latest"))
olhe(
  "Você usaria cvm_release_set() num artigo? A mensagem de erro acima explica o limite?"
)

# ---- 11. Cache local ----------------------------------------------------

passo("11. Cache")
print(cvm_cache_path())
print(cvm_cache_info())
confere(
  "o cache tem alguma coisa depois das leituras",
  nrow(cvm_cache_info()) > 0L
)
cvm_cache_clear("all", confirm = FALSE)
confere("depois de limpar, o cache fica vazio", nrow(cvm_cache_info()) == 0L)
olhe("A tabela do cache acima é útil para saber o que ocupa espaço?")

# ---- 12. Outros conjuntos, uma leitura de cada --------------------------

passo("12. Os outros conjuntos")
le <- function(...) suppressWarnings(suppressMessages(cvm_fetch(...)))
outros <- list(
  "itr/bpa" = le("itr", "bpa", ticker = "PETR4", year = 2025, basis = "con"),
  "fca/valor_mobiliario" = le(
    "fca",
    "valor_mobiliario",
    cnpj = petr,
    year = 2025
  ),
  "cgvn/praticas" = le("cgvn", "praticas", cnpj = petr, year = 2024),
  "vlmo/consolidado" = le("vlmo", "consolidado", cnpj = petr, year = 2024),
  "ipe/ipe" = le("ipe", "ipe", cnpj = petr, year = 2025),
  "recompra_acoes/recompra_acoes" = le("recompra_acoes", "recompra_acoes")
)
for (n in names(outros)) {
  cat(sprintf(
    "%-34s %7d linhas, %2d colunas\n",
    n,
    nrow(outros[[n]]),
    ncol(outros[[n]])
  ))
  confere(paste(n, "devolve linhas"), nrow(outros[[n]]) > 0L)
}
print(outros[["fca/valor_mobiliario"]][, c(
  "valor_mobiliario",
  "codigo_negociacao",
  "mercado"
)])
olhe("Os tickers da Petrobras acima estão certos?")

# ---- 13. Citação e documentação ----------------------------------------

passo("13. Citação e ajuda")
print(citation("cvmdata"))
confere("a citação traz o pacote e os dados", length(citation("cvmdata")) == 2L)
olhe(
  "Abra ?cvm_fetch e leia a seção 'Personal data': é o que você quer dizer ao usuário?"
)
olhe(
  "Abra o site https://sidneybissoli.github.io/cvmdata/ : a página inicial apresenta bem o pacote?"
)
olhe(
  "Abra https://doi.org/10.5281/zenodo.24260440 : o registro no Zenodo está como você quer?"
)

# ---- Placar --------------------------------------------------------------

placar()
