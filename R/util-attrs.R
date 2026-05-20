# Provenance metadata attached to every tibble returned by public
# fetcher functions. The five attributes are in English by design
# (naming doc v03 §5).

# Attach provenance attributes and the `cvm_tbl` S3 subclass.
#
# @param df A data frame coerced to a tibble.
# @param source One of "portal", "mirror", "cache".
# @param dataset Short identifier of the dataset ("cad", "itr", ...).
# @param table Identifier of the table within the dataset.
# @return A tibble of class `cvm_tbl` carrying five attributes.
cvm_attach_metadata <- function(df, source, dataset, table) {
  out <- tibble::as_tibble(df)
  attr(out, "source") <- source
  attr(out, "fetched_at") <- Sys.time()
  attr(out, "dataset") <- dataset
  attr(out, "table") <- table
  attr(out, "package_version") <- as.character(
    utils::packageVersion("cvmdata")
  )
  class(out) <- c("cvm_tbl", class(out))
  out
}
