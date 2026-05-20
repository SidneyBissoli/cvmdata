# CAD transformations. Per the YAML schema for `cad/companhias`, no
# shape-altering transformations are declared — only the universal
# normalisation of column names from SCREAMING_SNAKE_CASE to
# snake_case lowercase (naming doc v03 §0).
#
# Identifier-to-character coercion and date conversion happen earlier
# in `read_cvm_csv()`; this function operates on the parsed tibble.

transform_cad <- function(df, schema) {
  colnames(df) <- tolower(colnames(df))
  df
}
