devtools::load_all()  # ou install + library(cvmdata)

  # Tracer principal — espera ~48 linhas BPA do BCO BRASIL, 2 exercícios
  bb_bpa <- cvm_fetch("dfp", "bpa",
                      report_type = "ind",
                      companies   = "BCO BRASIL",
                      years       = 2024,
                      source      = "cvm")
  print(bb_bpa)
  dplyr::glimpse(bb_bpa)

  # Tabela sem variantes
  cc <- cvm_fetch("dfp", "composicao_capital",
                  companies = "BCO BRASIL",
                  years     = 2024,
                  source    = "cvm")
  print(cc)

  # composicao_capital com CD_CVM — exercita resolve_cd_cvm_via_submissao
  # (essa tabela não tem cd_cvm nativo). Espera mensagem informativa
  # "i Resolving CD_CVM 001023 via "dfp"/submissao for 2024 ...".
  cc_cd <- cvm_fetch("dfp", "composicao_capital",
                     companies = "001023",
                     years     = 2024,
                     source    = "cvm")
  print(cc_cd)

  # submissao — header do documento DFP anual. Tabela com cd_cvm nativo,
  # então CD_CVM filtra direto (sem disparar resolve_cd_cvm_via_submissao).
  sub <- cvm_fetch("dfp", "submissao",
                   companies = "001023",
                   years     = 2024,
                   source    = "cvm")
  print(sub)

  # parecer — texto livre (declarações de diretores e auditores). Sem
  # variantes ind/con, sem cd_cvm nativo, então CD_CVM passaria pelo
  # lookup via submissao; aqui usamos CNPJ direto.
  par <- cvm_fetch("dfp", "parecer",
                   companies = "00.000.000/0001-91",  # BCO BRASIL
                   years     = 2024,
                   source    = "cvm")
  print(par)

  par |>
    filter(row_number()==4) |>
    pull(txt_parecer_decl)
  
  
  # DMPL (16 cols com coluna_df) — VALE tem 3 versões; só v3 deve voltar
  vale_dmpl <- cvm_fetch("dfp", "dmpl",
                         report_type = "con",
                         companies   = "VALE S.A.",
                         years       = 2024,
                         source      = "cvm")
  unique(vale_dmpl$versao)   # esperado: "3"
  vale_dmpl
  dplyr::glimpse(vale_dmpl)
  
  
  # Multi-companhia via CD_CVM
  multi <- cvm_fetch(dataset = "dfp", table = "bpa",
                     report_type = "ind",
                     companies   = c("9512", "4170"),
                     years       = 2024,
                     source      = "cvm")
  sort(unique(multi$cd_cvm))   # esperado: c("004170", "009512")

  # Busca textual com abreviação BANCO ↔ BCO
  # "banco brasil" exige os DOIS tokens — só BCO BRASIL S.A. casa,
  # então não dispara o prompt de múltiplas matches.
  bancos <- cvm_fetch("dfp", "bpa",
                      report_type = "ind",
                      companies   = "banco brasil",
                      years       = 2024,
                      source      = "cvm")
  unique(bancos$denom_cia)   # esperado: "BCO BRASIL S.A."

  # Busca textual ambígua — em interactive() apresenta utils::menu()
  # para o usuário escolher uma das matches (ou "All of the above");
  # em batch (CI/script) aborta com cvmdata_error_input listando todas
  # as matches. Política do CLAUDE.md §2.7.
  bancos_multi <- cvm_fetch("dfp", "bpa",
                            report_type = "ind",
                            companies   = "banco",
                            years       = 2024,
                            source      = "cvm")

  # Discovery
  cvm_datasets()
  cvm_tables("dfp")
  cvm_dataset_years("dfp")
  cvm_dataset_years("cad")   # esperado: NA_integer_

  # Default years=NULL → último ano publicado pela CVM. Quando há
  # filter por companies, faz fallback descendente: se max year não
  # tem dados da companhia (ex.: 2026 lista só agros com calendário
  # fiscal não-civil), emite cvmdata_warn_year_fallback e desce até
  # encontrar (limite 3 anos). Para BCO BRASIL hoje (calendário civil),
  # deve cair em 2025.
  latest <- cvm_fetch("dfp", "bpa",
                      report_type = "ind",
                      companies   = "BCO BRASIL",
                      source      = "cvm")
  unique(latest$dt_refer)   # esperado: 2025-12-31
  