# Tests for the dated snapshots of the mirror on the client side
# (decision of 2026-10-25): resolving `cvmdata.mirror_release` to a
# snapshot, building the inventory from the snapshot's manifest, the
# `release` provenance attribute, and the integrity check of every
# parquet against the sha256 the sidecar publishes (ROADMAP "Integridade
# do download"). The GitHub API and the downloads are mocked as in
# helper-mirror-mock.R; the bytes of the "old" snapshot are the 2025
# fixture of the same partition, so a pinned read is told apart from
# the latest one by the reference dates it returns.

s20 <- "mirror-companhias-dfp-snapshot-2026-10-20"
s27 <- "mirror-companhias-dfp-snapshot-2026-10-27"
bpa_name <- "bpa__report_type.ind__year.2024__part-0.parquet"
bpa_rel <- "bpa/report_type=ind/year=2024/part-0.parquet"
old_fx <- function() test_path("fixtures", "mirror-dfp-bpa-ind-2025.parquet")

# Latest = the 2024 fixture, published as snapshot 2026-10-27; snapshot
# 2026-10-20 holds the 2025 fixture under the same partition name.
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
  cvmdata:::mirror_assets_cache_clear()
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

# Resolving the release -------------------------------------------------

test_that("mirror_pick_snapshot takes the latest date on or before the pin", {
  dates <- c("2026-10-27", "2026-10-20", "2026-11-03")
  expect_identical(
    cvmdata:::mirror_pick_snapshot(dates, "2026-10-25", "dfp"),
    "2026-10-20"
  )
  expect_identical(
    cvmdata:::mirror_pick_snapshot(dates, "2026-10-27", "dfp"),
    "2026-10-27"
  )
  expect_identical(
    cvmdata:::mirror_pick_snapshot(dates, "2027-01-01", "dfp"),
    "2026-11-03"
  )
  expect_error(
    cvmdata:::mirror_pick_snapshot(dates, "2026-10-01", "dfp"),
    "2026-10-20",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvmdata:::mirror_pick_snapshot(character(0L), "2026-10-01", "dfp"),
    "no dated snapshots",
    class = "cvmdata_error_input"
  )
  expect_error(
    cvmdata:::mirror_pick_snapshot(NULL, "2026-10-01", "dfp"),
    class = "cvmdata_error_input"
  )
})

test_that("the sidecar's snapshot fields are read and tolerated when absent", {
  local_mirror_session()
  mock <- build_snapshot_mock()
  inventory <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets("companhias", "dfp", release = "latest")
  )
  expect_identical(attr(inventory, "source_hash"), "h27")
  expect_identical(attr(inventory, "snapshot"), "2026-10-27")
  expect_identical(attr(inventory, "snapshots"), c("2026-10-20", "2026-10-27"))
  expect_identical(attr(inventory, "release_tag"), s27)
  expect_false(attr(inventory, "pinned"))
  expect_identical(
    inventory$sha256[inventory$name == bpa_name],
    fixture_sha256(dfp_fx())
  )

  cvmdata:::mirror_assets_cache_clear()
  plain <- httr2::with_mocked_responses(
    build_mock(list(list(name = bpa_name, parquet = dfp_fx())), hash = "h"),
    cvmdata:::mirror_list_assets("companhias", "dfp", release = "latest")
  )
  expect_identical(attr(plain, "snapshot"), NA_character_)
  expect_identical(attr(plain, "snapshots"), character(0L))
  expect_identical(attr(plain, "release_tag"), "mirror-companhias-dfp-latest")
  expect_true(all(is.na(plain$sha256)))
})

test_that("a pinned inventory points every partition into its snapshot", {
  local_mirror_session()
  mock <- build_snapshot_mock()
  inventory <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets("companhias", "dfp", release = "2026-10-25")
  )
  expect_true(attr(inventory, "pinned"))
  expect_identical(attr(inventory, "release_tag"), s20)
  expect_identical(attr(inventory, "snapshot"), "2026-10-20")
  expect_identical(attr(inventory, "source_hash"), "h20")
  expect_identical(inventory$name, bpa_name)
  expect_identical(
    inventory$url,
    sprintf(
      "https://github.com/SidneyBissoli/cvmdata/releases/download/%s/%s",
      s20,
      bpa_name
    )
  )
  expect_identical(inventory$sha256, fixture_sha256(old_fx()))
  expect_identical(inventory$size_bytes, as.integer(file.info(old_fx())$size))

  # The inventory is cached per release: the two pins live side by side.
  latest <- cvmdata:::mirror_list_assets(
    "companhias",
    "dfp",
    release = "latest"
  )
  expect_identical(attr(latest, "release_tag"), s27)
  expect_identical(
    cvmdata:::mirror_resolved_release("companhias", "dfp", "2026-10-25"),
    s20
  )
  expect_identical(
    cvmdata:::mirror_resolved_release("companhias", "dfp", "latest"),
    s27
  )
  expect_identical(
    cvmdata:::mirror_resolved_release("companhias", "itr", "latest"),
    NA_character_
  )
})

test_that("a pin equal to the latest snapshot reuses the latest rows", {
  local_mirror_session()
  mock <- build_snapshot_mock()
  inventory <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_list_assets("companhias", "dfp", release = "2026-10-30")
  )
  expect_true(attr(inventory, "pinned"))
  expect_identical(attr(inventory, "release_tag"), s27)
  expect_identical(attr(inventory, "source_hash"), "h27")
  expect_identical(
    inventory$url[inventory$name == bpa_name],
    sprintf("https://example.test/%s", bpa_name)
  )
})

test_that("a pin before the first snapshot, or without snapshots, is refused", {
  local_mirror_session()
  expect_error(
    httr2::with_mocked_responses(
      build_snapshot_mock(),
      cvmdata:::mirror_list_assets("companhias", "dfp", release = "2026-10-01")
    ),
    "2026-10-20",
    class = "cvmdata_error_input"
  )
  cvmdata:::mirror_assets_cache_clear()
  expect_error(
    httr2::with_mocked_responses(
      build_mock(list(list(name = bpa_name, parquet = dfp_fx())), hash = "h"),
      cvmdata:::mirror_list_assets("companhias", "dfp", release = "2026-10-25")
    ),
    "no dated snapshots",
    class = "cvmdata_error_input"
  )
})

test_that("a snapshot whose manifest cannot be read aborts with the URL", {
  local_mirror_session()
  mock <- build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h27",
    sidecar = list(
      snapshot = "2026-10-27",
      snapshots = c("2026-10-20", "2026-10-27")
    )
  )
  expect_error(
    httr2::with_mocked_responses(
      mock,
      cvmdata:::mirror_list_assets("companhias", "dfp", release = "2026-10-25")
    ),
    s20,
    class = "cvmdata_error_http"
  )
})

test_that("a manifest without a release pointer is refused", {
  sidecar <- list(
    hash = "h",
    data = stats::setNames(list("c"), bpa_rel),
    releases = list(),
    files = NULL
  )
  expect_error(
    cvmdata:::mirror_inventory_from_manifest(sidecar, "o/r", s20),
    class = "cvmdata_error_parse"
  )
  empty <- cvmdata:::mirror_inventory_from_manifest(
    list(hash = "h", data = list()),
    "o/r",
    s20
  )
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), c("name", "url", "size_bytes", "sha256"))
})

test_that("mirror_assets_to_tibble matches the files map by public name", {
  assets <- list(
    list(name = bpa_name, browser_download_url = "u1", size = 10L),
    list(name = "__source_hash.json", browser_download_url = "u2", size = 1L),
    list(
      name = "bpa__report_type.ind__year.2024__history.parquet",
      browser_download_url = "u3",
      size = 5L
    )
  )
  files <- stats::setNames(list(list(sha256 = "abc", size = 10)), bpa_rel)
  out <- cvmdata:::mirror_assets_to_tibble(assets, files)
  expect_identical(out$sha256, c("abc", NA, NA))
  expect_identical(out$size_bytes, c(10L, 1L, 5L))
  out <- cvmdata:::mirror_assets_to_tibble(assets, NULL)
  expect_identical(out$sha256, rep(NA_character_, 3L))
})

# Reading under a pin ----------------------------------------------------

test_that("cvm_fetch under a pinned date reads the snapshot's bytes", {
  cache_root <- local_mirror_session(release = "2026-10-25")
  mock <- build_snapshot_mock()

  pinned <- fetch_bpa(mock)
  expect_s3_class(pinned, "cvm_tbl")
  expect_identical(attr(pinned, "source"), "mirror")
  expect_identical(attr(pinned, "release"), s20)
  expect_identical(ref_years(pinned), "2025")
  expect_identical(unique(pinned$year), 2024L)
  # The pin does not write the dataset-level sidecar of the L3 cache.
  expect_false(file.exists(file.path(
    cache_root,
    "parquet",
    "companhias",
    "dfp",
    "__source_hash.json"
  )))

  # Back to latest in the same session: the cached copy carries the
  # other snapshot's bytes, and the sha256 check replaces it.
  options(cvmdata.mirror_release = "latest")
  latest <- fetch_bpa(mock)
  expect_identical(attr(latest, "release"), s27)
  expect_identical(ref_years(latest), "2024")
  l3 <- cvmdata:::mirror_l3_path("dfp", "bpa", 2024L, "ind")
  expect_identical(fixture_sha256(l3), fixture_sha256(dfp_fx()))

  # And back to the pin: replaced again, no error.
  options(cvmdata.mirror_release = "2026-10-20")
  again <- fetch_bpa(mock)
  expect_identical(attr(again, "release"), s20)
  expect_identical(ref_years(again), "2025")
})

test_that("the release attribute is the -latest tag without snapshots", {
  local_mirror_session()
  out <- fetch_bpa(build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h"
  ))
  expect_identical(attr(out, "release"), "mirror-companhias-dfp-latest")
})

test_that("the release attribute is NA off the mirror and prints when set", {
  cvm <- cvmdata:::cvm_attach_metadata(
    data.frame(a = 1),
    source = "cvm",
    group = "companhias",
    dataset = "cad",
    table = "companhias"
  )
  expect_identical(attr(cvm, "release"), NA_character_)
  expect_true("release" %in% cvmdata:::cvm_tbl_attr_names)
  msgs <- character()
  withCallingHandlers(
    print(cvm),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_false(any(grepl("release", msgs, fixed = TRUE)))

  mirror <- cvm
  attr(mirror, "source") <- "mirror"
  attr(mirror, "release") <- s20
  expect_message(print(mirror), s20, fixed = TRUE)

  # Two reads from different releases reconcile to "mixed".
  other <- mirror
  attr(other, "release") <- s27
  both <- vctrs::vec_rbind(mirror, other)
  expect_identical(attr(both, "release"), "mixed")
})

test_that("a pin drops the history superseded after its date", {
  history <- arrow::read_parquet(
    test_path("fixtures", "mirror-dfp-dre-con-2023-history.parquet")
  )
  current <- arrow::read_parquet(
    test_path("fixtures", "mirror-dfp-dre-con-2023.parquet")
  )
  current$superseded_at <- NA_character_
  history$superseded_at <- as.character(history$superseded_at)
  df <- vctrs::vec_rbind(
    current[, "superseded_at", drop = FALSE],
    history[, "superseded_at", drop = FALSE]
  )
  kept <- cvmdata:::mirror_drop_history_after(df, "2024-05-14")
  expect_identical(sum(is.na(kept$superseded_at)), nrow(current))
  expect_setequal(
    unique(kept$superseded_at[!is.na(kept$superseded_at)]),
    c("2024-03-25", "2024-05-14")
  )
  expect_identical(cvmdata:::mirror_drop_history_after(df, NA_character_), df)
  expect_identical(
    cvmdata:::mirror_drop_history_after(df, "2026-10-27"),
    df
  )
})

test_that("cvm_versions reads the history from -latest under a pin", {
  local_mirror_session(release = "2026-10-27")
  entries <- list(
    list(
      name = "dre__report_type.con__year.2023__part-0.parquet",
      parquet = test_path("fixtures", "mirror-dfp-dre-con-2023.parquet")
    ),
    list(
      name = "dre__report_type.con__year.2023__history.parquet",
      parquet = test_path("fixtures", "mirror-dfp-dre-con-2023-history.parquet")
    )
  )
  mock <- build_mock(
    entries,
    hash = "h27",
    files = TRUE,
    sidecar = list(snapshot = "2026-10-27", snapshots = list("2026-10-27"))
  )
  out <- httr2::with_mocked_responses(
    mock,
    cvm_versions("dfp", "dre", year = 2023, basis = "con")
  )
  expect_identical(attr(out, "release"), s27)
  expect_identical(nrow(out), 40L)
  expect_true(any(out$history_source == "rad"))
})

# Integrity of the download ------------------------------------------------

test_that("a cached parquet that does not match the sidecar is replaced", {
  local_mirror_session()
  mock <- build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h",
    files = TRUE
  )
  l3 <- cvmdata:::mirror_l3_path("dfp", "bpa", 2024L, "ind")
  dir.create(dirname(l3), recursive = TRUE)
  writeBin(as.raw(1:100), l3)

  out <- fetch_bpa(mock)
  expect_identical(ref_years(out), "2024")
  expect_identical(fixture_sha256(l3), fixture_sha256(dfp_fx()))
})

test_that("a download that does not match the sidecar is discarded", {
  local_mirror_session()
  mock <- build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h",
    sidecar = list(
      files = stats::setNames(
        list(list(
          sha256 = strrep("0", 64L),
          size = file.info(dfp_fx())$size
        )),
        bpa_rel
      )
    )
  )
  expect_error(
    fetch_bpa(mock),
    "does not match",
    class = "cvmdata_error_http_integrity"
  )
  expect_false(file.exists(cvmdata:::mirror_l3_path(
    "dfp",
    "bpa",
    2024L,
    "ind"
  )))
})

test_that("a size mismatch is caught without a sha256", {
  path <- withr::local_tempfile()
  writeBin(as.raw(1:10), path)
  expect_true(cvmdata:::mirror_file_matches(path, NA_character_, NA_integer_))
  expect_true(cvmdata:::mirror_file_matches(path, NA_character_, 10L))
  expect_false(cvmdata:::mirror_file_matches(path, NA_character_, 11L))
  expect_true(cvmdata:::mirror_file_matches(
    path,
    toupper(unname(tools::sha256sum(path))),
    10L
  ))
  expect_false(cvmdata:::mirror_file_matches(path, strrep("a", 64L), 10L))
})

test_that("a parquet DuckDB cannot read is removed from the cache", {
  local_mirror_session()
  bad <- withr::local_tempfile(fileext = ".parquet")
  writeBin(as.raw(1:100), bad)
  mock <- build_mock(list(list(name = bpa_name, parquet = bad)), hash = "h")
  expect_error(fetch_bpa(mock), class = "cvmdata_error_parse")
  expect_false(file.exists(cvmdata:::mirror_l3_path(
    "dfp",
    "bpa",
    2024L,
    "ind"
  )))
})

test_that("a verified inventory evicts only the history copies", {
  cache_root <- local_mirror_session()
  mock <- build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h1",
    files = TRUE
  )
  fetch_bpa(mock)
  l3 <- cvmdata:::mirror_l3_path("dfp", "bpa", 2024L, "ind")
  hist <- file.path(dirname(l3), "history.parquet")
  writeBin(as.raw(1:10), hist)

  cvmdata:::mirror_assets_cache_clear()
  mock2 <- build_mock(
    list(list(name = bpa_name, parquet = dfp_fx())),
    hash = "h2",
    files = TRUE
  )
  expect_no_message(fetch_bpa(mock2), message = "evicted")
  expect_true(file.exists(l3))
  expect_false(file.exists(hist))
  expect_identical(
    readLines(file.path(
      cache_root,
      "parquet",
      "companhias",
      "dfp",
      "__source_hash.json"
    )),
    "h2"
  )
})

# The sidecar as GitHub serves it ------------------------------------------

test_that("the sidecar is parsed when served as application/octet-stream", {
  skip_if_not_installed("jsonlite")
  # GitHub release assets come with this content type; httr2 refuses to
  # parse JSON under it by default, and until 2026-10-25 the refusal was
  # swallowed into `hash = NA`, so no client ever read the sidecar.
  payload <- jsonlite::toJSON(
    list(
      hash = "h25",
      snapshot = "2026-10-25",
      snapshots = "2026-10-25",
      releases = stats::setNames(list(s27), bpa_rel),
      files = stats::setNames(list(list(sha256 = "abc", size = 10)), bpa_rel)
    ),
    auto_unbox = TRUE
  )
  mock <- function(req) {
    httr2::response(
      status_code = 200L,
      headers = list("Content-Type" = "application/octet-stream"),
      body = charToRaw(as.character(payload))
    )
  }
  sidecar <- httr2::with_mocked_responses(
    mock,
    cvmdata:::mirror_read_sidecar("https://example.test/__source_hash.json")
  )
  expect_identical(sidecar$hash, "h25")
  expect_identical(sidecar$snapshot, "2026-10-25")
  # A single date is written by jsonlite as a scalar.
  expect_identical(sidecar$snapshots, "2026-10-25")
  expect_identical(sidecar$releases[[bpa_rel]], s27)
  expect_identical(sidecar$files[[bpa_rel]]$sha256, "abc")
})
