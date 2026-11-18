# syntax=docker/dockerfile:1
#
# The environment of the ETL robots (etl-mirror, etl-rad, zenodo-edition),
# built once and reused by digest.
#
# Why (2026-11-18): every robot run used to rebuild its environment from
# three sources outside our control, the apt mirror of the runner, P3M and
# the R download of setup-r, and a slow mirror alone failed the job before
# the robot started (2026-10-23, 2026-10-27 twice, 2026-11-18). Here the
# environment is built when its inputs change, tested inside the image
# (smoke.R) and pushed to GHCR; a robot run only pulls it and installs the
# package from the checkout (R CMD INSTALL, no network).
#
# Every input is pinned, so the same inputs give the same environment:
#   - the base image by digest (Dependabot, docker ecosystem, bumps it);
#   - CRAN by a dated P3M snapshot (P3M_DATE; refresh-etl-image.yaml
#     proposes a newer date once a month);
#   - the gh CLI by version and sha256.
# The image tag is a hash of these inputs plus the dependency fields of
# DESCRIPTION (see etl-image.yaml): a change in any of them is a new image.

FROM docker.io/rocker/r-ver:4.6.2@sha256:4383092318935c298533466f753354a7dfdc75a6e12edfb93a0f13c8a97135f9

LABEL org.opencontainers.image.source="https://github.com/SidneyBissoli/cvmdata" \
      org.opencontainers.image.description="Runtime of the cvmdata ETL robots" \
      org.opencontainers.image.licenses="MIT"

# Dated snapshot of CRAN, Linux binaries for this Ubuntu release.
ARG P3M_DATE=2026-11-17
ARG GH_VERSION=2.103.3
ARG GH_SHA256=4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d

# git: actions/checkout and the release scripts; unzip: utils::unzip()
# goes to the Info-ZIP binary, which reads Deflate64 (the internal one
# skips those members with only a warning); ca-certificates and curl:
# the gh download below.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git unzip ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# gh CLI, the only external command the ETL calls (inst/etl/util-gh.R).
RUN curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
 && echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/gh.tar.gz -C /tmp \
 && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
 && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

# The snapshot becomes the default repository of the image, so nothing at
# run time can reach a newer CRAN by accident.
RUN echo "options(repos = c(CRAN = 'https://p3m.dev/cran/__linux__/resolute/${P3M_DATE}'))" \
      >> "${R_HOME}/etc/Rprofile.site"

# pak resolves the dependencies and installs their system libraries.
RUN Rscript -e "install.packages('pak')"

# The hard dependencies of cvmdata plus what inst/etl loads: arrow,
# digest, dplyr, jsonlite, pointblank, tidyselect, withr, xml2. Only the
# DESCRIPTION goes in, not the package: the package is installed by each
# robot run from its own checkout.
COPY DESCRIPTION /tmp/cvmdata/DESCRIPTION
RUN Rscript -e "pak::pkg_install(c('deps::/tmp/cvmdata', 'arrow', 'digest', 'dplyr', 'jsonlite', 'pointblank', 'tidyselect', 'withr', 'xml2'), dependencies = NA, upgrade = FALSE)" \
 && Rscript -e "pak::cache_clean()" \
 && rm -rf /tmp/cvmdata /var/lib/apt/lists/*

COPY .github/etl-image/smoke.R /opt/cvmdata-etl/smoke.R
