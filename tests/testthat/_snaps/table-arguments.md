# the rendered help section is current

    Code
      cat(doc_arguments_by_table(), sep = "\n")
    Output
      Which arguments apply depends on the table. The rules below are generated from the package's table schemas, the same ones the argument checks read, for the 77 tables in 9 datasets. An argument passed to a table it does not apply to aborts with `cvmdata_error_input` before anything is downloaded; nothing is silently ignored.
      
      * `year` and `from`/`to`: every table published one file per year. Not for `cad`: `companhias`; `recompra_acoes`: `intermediarios`, `quantidades`, `recompra_acoes`, a single snapshot. A `year` before the table's first year is refused (a `from`/`to` window is cut to it instead). Most tables start with their dataset; these start later: `dfp/composicao_capital` (2020), `fre/acao_entregue` (2023), `fre/administrador_PCD` (2023), `fre/administrador_declaracao_genero` (2023), `fre/administrador_declaracao_raca` (2023), `fre/empregado_PCD` (2023), `fre/empregado_local_declaracao_genero` (2023), `fre/empregado_local_declaracao_raca` (2023), `fre/empregado_local_faixa_etaria` (2023), `fre/empregado_posicao_declaracao_genero` (2023), `fre/empregado_posicao_declaracao_raca` (2023), `fre/empregado_posicao_faixa_etaria` (2023), `fre/empregado_posicao_local` (2023), `fre/mercado_estrangeiro` (2019), `fre/remuneracao_acao` (2023), `fre/remuneracao_variavel` (2023), `fre/titular_valor_mobiliario` (2018), `fre/titulo_exterior` (2016), `itr/composicao_capital` (2020).
      * Years from which the CVM publishes the file with its header only are refused too: `fca/departamento_acionistas` (2024).
      * `basis`: required, with no default, in `dfp` and `itr`: `bpa`, `bpp`, `dfc_md`, `dfc_mi`, `dmpl`, `dra`, `dre`, `dva`. Refused in every other table.
      * `reading`: only in `dfp` and `itr`: `bpa`, `bpp`, `dfc_md`, `dfc_mi`, `dmpl`, `dra`, `dre`, `dva` (the tables with `ordem_exerc`).
      * `as_of`: only in `cad`: `companhias`.
      * `cnpj`/`ticker` in a table without an issuer column: `recompra_acoes`: `intermediarios`, `quantidades` keep the rows linked to the issuer's rows in `recompra_acoes/recompra_acoes`.
      * [cvm_versions()]: every table except `cad`: `companhias`; `cgvn`, `dfp`, `fca`, `fre` and `itr`: `submissao`; `ipe`: `ipe`; `recompra_acoes`: `intermediarios`, `quantidades`, `recompra_acoes`; `vlmo`: `consolidado`, `submissao`, which already return every row the CVM publishes.

