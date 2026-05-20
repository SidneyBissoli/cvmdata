# Hierarchical condition classes used across the package.
#
# Errors inherit from "cvmdata_error" (parent for `tryCatch()` capture);
# warnings inherit from "cvmdata_warn". The hierarchy is documented in
# the naming doc v03 §6.1 with the refinement from Rodada 3.0.2.

# Wrap `cli::cli_abort()` so that the parent class "cvmdata_error" is
# always appended. Callers pass the specific subclass via `class`.
cvmdata_abort <- function(message,
                          class = NULL,
                          ...,
                          call = rlang::caller_env(),
                          .envir = parent.frame()) {
  classes <- unique(c(class, "cvmdata_error"))
  cli::cli_abort(
    message,
    class = classes,
    call = call,
    ...,
    .envir = .envir
  )
}

# Wrap `cli::cli_warn()` analogously. Parent class is "cvmdata_warn".
cvmdata_warn <- function(message,
                         class = NULL,
                         ...,
                         .envir = parent.frame()) {
  classes <- unique(c(class, "cvmdata_warn"))
  cli::cli_warn(
    message,
    class = classes,
    ...,
    .envir = .envir
  )
}
