# Extracted from test-mirror-snapshot.R:282

# prequel ----------------------------------------------------------------------
s20 <- "mirror-companhias-dfp-snapshot-2026-10-20"
s27 <- "mirror-companhias-dfp-snapshot-2026-10-27"
bpa_name <- "bpa__report_type.ind__year.2024__part-0.parquet"
bpa_rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
old_fx <- function() test_path("fixtures", "mirror-dfp-bpa-ind-2025.parquet")
build_snapshot_mock <- function(...) {
  manifest20 <- list(
    hash = "h20",
    snapshot = "2026-10-20",
    snapshots = list("2026-10-20"),
    data = stats::setNames(list("c20"), bpa_rel),
    releases = stats::setNames(list(s20), bpa_rel),
    files = stats::setNames(
      list(list(
        sha256 = fixture_sha256(old_fx()),
        size = file.info(old_fx())$size
      )),
      bpa_rel
    )
  )
  build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h27",
    files = TRUE,
    sidecar = list(
      snapshot = "2026-10-27",
      snapshots = c("2026-10-20", "2026-10-27")
    ),
    snapshots = stats::setNames(list(manifest20), s20),
    snapshot_assets = stats::setNames(
      list(list(list(name = bpa_name, parquet = old_fx()))),
      s20
    ),
    ...
  )
}
local_mirror_session <- function(release = "latest", envir = parent.frame()) {
  mirror_assets_cache_clear()
  cache_root <- withr::local_tempdir(.local_envir = envir)
  withr::local_options(
    cvmdata.cache_dir = cache_root,
    cvmdata.mirror_release = release,
    lifecycle_verbosity = "quiet",
    .local_envir = envir
  )
  cache_root
}
fetch_bpa <- function(mock) {
  httr2::with_mocked_responses(
    mock,
    cvm_fetch("dfp", "bpa", year = 2024, basis = "ind", source = "mirror")
  )
}
ref_years <- function(df) unique(format(as.Date(df$dt_refer), "%Y"))

# test -------------------------------------------------------------------------
cache_root <- local_mirror_session(release = "2026-10-25")
mock <- build_snapshot_mock()
pinned <- fetch_bpa(mock)
expect_s3_class(pinned, "cvm_tbl")
expect_identical(attr(pinned, "source"), "mirror")
expect_identical(attr(pinned, "release"), s20)
expect_identical(ref_years(pinned), "2025")
expect_identical(unique(pinned$year), 2024L)
