# Provenance metadata attached to every tibble returned by public
# fetcher functions. The six attributes are in English by design
# (naming doc v03 §5); `group` was added in Sessao 08 of v0.1.0.9000
# (see data-raw/decisions/cvmdata_arquitetura_grupos_decisao_v2.md §4.6)
# so the returned tibble carries the CKAN group slug alongside the
# dataset slug -- otherwise a downstream consumer needs the package's
# internal `dataset_group()` lookup just to know where the data came
# from.

# Attach provenance attributes and the `cvm_tbl` S3 subclass.
#
# @param df A data frame coerced to a tibble.
# @param source One of "portal", "mirror", "cache".
# @param group CKAN group slug (e.g. "companhias").
# @param dataset Short identifier of the dataset ("cad", "itr", ...).
# @param table Identifier of the table within the dataset.
# @return A tibble of class `cvm_tbl` carrying six attributes.
cvm_attach_metadata <- function(df, source, group, dataset, table) {
  out <- tibble::as_tibble(df)
  attr(out, "source") <- source
  attr(out, "fetched_at") <- Sys.time()
  attr(out, "group") <- group
  attr(out, "dataset") <- dataset
  attr(out, "table") <- table
  attr(out, "package_version") <- as.character(
    utils::packageVersion("cvmdata")
  )
  class(out) <- c("cvm_tbl", class(out))
  out
}
