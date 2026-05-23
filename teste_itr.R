# Smoke local do ITR ponta-a-ponta contra o portal CVM real.
# Roda do diretório raiz do pacote. source = "cvm" porque o mirror
# ainda é stub (Fase F).

devtools::load_all()

# --- 1. Descoberta ---------------------------------------------------

cvm_datasets()
cvm_tables("itr")
cvm_dataset_years("itr")  # HEAD probing no listing do portal

# --- 2. Tracer principal: BPA individual, último ano disponível ------

bpa_ind <- cvm_fetch(
  dataset     = "itr",
  table       = "bpa",
  report_type = "ind",
  companies   = "BCO BRASIL",
  source      = "cvm"
)
bpa_ind
attributes(bpa_ind)[c("source", "fetched_at", "dataset", "table")]

# Sanity: cadência trimestral (até 3 datas distintas de DT_REFER no ano).
unique(bpa_ind$dt_refer)

# Sanity: multiply_by_scale aplicado (Ativo Total ~ trilhões, não milhares).
subset(bpa_ind, cd_conta == "1" & ordem_exerc == "ÚLTIMO",
       select = c(dt_refer, ds_conta, vl_conta))

# --- 3. BPA consolidado por CNPJ + ano explícito ---------------------

bpa_con_2023 <- cvm_fetch(
  "itr", "bpa",
  report_type = "con",
  companies   = "47.960.950/0001-21",  # MAGAZINE LUIZA
  years       = 2023L,
  source      = "cvm"
)
bpa_con_2023

# --- 4. composicao_capital (sem variantes, sem multiply_by_scale) ----

cc <- cvm_fetch(
  "itr", "composicao_capital",
  companies = "001023",
  years     = 2024L,
  source    = "cvm"
)
cc

# --- 5. submissao (header dos documentos) ----------------------------

sub <- cvm_fetch(
  "itr", "submissao",
  companies = "001023",
  years     = 2024L,
  source    = "cvm"
)
sub

# --- 6. parecer (texto livre, sem cd_cvm) ----------------------------

par <- cvm_fetch(
  "itr", "parecer",
  companies = "00.000.000/0001-91",  # BCO BRASIL
  years     = 2024L,
  source    = "cvm"
)
par




# --- 7. DRE individual, multi-ano (3 trimestres × 2 anos) ------------

dre_ind <- cvm_fetch(
  "itr", "dre",
  report_type = "ind",
  companies   = "001023",
  years       = 2023:2024,
  source      = "cvm"
)
dre_ind
table(dre_ind$dt_refer)

# --- 8. Erros esperados ----------------------------------------------

# report_type obrigatório para tabelas com variantes
try(cvm_fetch("itr", "bpa", years = 2024, source = "cvm"))

# report_type proibido para tabelas sem variantes
try(cvm_fetch("itr", "composicao_capital", years = 2024,
              source = "cvm", report_type = "ind"))

# Companhia inexistente — texto sem match
try(cvm_fetch("dfp", "bpa", report_type = "ind",
              companies = "EMPRESA QUE NAO EXISTE XYZ",
              years = 2024, source = "cvm"))
