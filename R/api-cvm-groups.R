# Static taxonomy of the 18 CKAN groups published by the CVM Open Data
# Portal, mapped to the 5 data-contract fetchers `cvmdata` exposes.
# Verified against <https://dados.cvm.gov.br/group/> on 2026-05-25; see
# `data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` for the
# rationale behind the contract assignments. The table is intentionally
# embedded in code (not a `inst/extdata/` CSV) because it changes only
# when CVM reorganises CKAN -- a rare event -- and shipping it as data
# would add a moving part without ergonomic benefit.

# Returned as a tibble row-by-row to keep the source readable. Order
# here is alphabetical by `group`; `cvm_groups()` re-sorts defensively
# so a future reorganisation of the source does not silently break the
# downstream invariant.
.cvm_groups_table <- function() {
  tibble::tibble(
    group = c(
      "administradores",
      "agentes-autonomos",
      "agentes-fiduciarios",
      "atividade-sancionadora",
      "atos-declaratorios",
      "auditores",
      "companhias",
      "consultores-de-valores-mobiliarios",
      "coordenadores-de-ofertas",
      "emissores-de-cepac",
      "fundos-de-investimento",
      "fundos-de-investimento-imobiliarios",
      "fundos-estruturados",
      "investidores-nao-residentes",
      "ofertas-publicas",
      "participantes-intermediarios",
      "plataformas-de-crowdfunding",
      "securitizadoras"
    ),
    n_datasets = c(
      2L, 1L, 1L, 1L, 1L, 1L, 12L, 1L, 1L, 1L,
      22L, 4L, 10L, 1L, 2L, 1L, 1L, 4L
    ),
    contract = c(
      "agent", "agent", "agent", "event", "event", "agent", "issuer",
      "agent", "agent", "issuer", "fund", "fund", "fund", "agent",
      "offering", "agent", "offering", "issuer"
    )
  )
}

#' List the CVM CKAN groups
#'
#' Returns the 18 thematic groups published by the CVM Open Data Portal
#' (`<https://dados.cvm.gov.br/group/>`), each with the number of
#' datasets the portal exposes for it and the canonical `cvmdata`
#' fetcher contract that covers it.
#'
#' v0.1.0.9000 implements only the `companhias` group (via
#' [issuer_fetch()]); the remaining 17 rows document the planned
#' v0.2-v0.8 coverage so users can navigate the universe of CVM data
#' before the corresponding fetchers ship. Calls to the four
#' non-`issuer` fetchers in v0.1.0.9000 abort with
#' `cvmdata_error_input_group`; see [fund_fetch()], [agent_fetch()],
#' [offering_fetch()] and [event_fetch()].
#'
#' The `n_datasets` column reports the totals published by CVM, not the
#' count currently implemented in the package. The mapping between
#' groups and contracts is fixed for the lifetime of v0.1.x; see
#' `data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md` for the
#' rationale.
#'
#' @return A tibble with 18 rows, sorted alphabetically by `group`.
#'   Columns:
#'   * `group` (character) -- the CKAN slug (e.g. `"companhias"`,
#'     `"fundos-de-investimento"`).
#'   * `n_datasets` (integer) -- count of datasets the CVM portal
#'     publishes under this group.
#'   * `contract` (character) -- one of `"issuer"`, `"fund"`, `"agent"`,
#'     `"offering"`, `"event"`. Identifies the `cvmdata` fetcher that
#'     covers (or will cover) the group.
#'
#' @examples
#' cvm_groups()
#'
#' # All groups served by issuer_fetch()
#' g <- cvm_groups()
#' g[g$contract == "issuer", ]
#' @family discovery
#' @seealso [cvm_datasets()], [issuer_fetch()]
#' @export
cvm_groups <- function() {
  out <- .cvm_groups_table()
  out[order(out$group), , drop = FALSE]
}
