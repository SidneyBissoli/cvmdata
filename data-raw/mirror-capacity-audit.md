# Mirror capacity audit — Sessao 3.11

_Generated: 2026-05-23 14:07:06 -03_

## Methodology

1. **Inventory**: 36 datasets across 13 top-level CVM domains within v0.1-v1.0 scope.
2. **HEAD probe**: byte sizes extracted from Apache directory listings on `dados.cvm.gov.br`.
3. **Parquet ratio**: three archetypes downloaded, unzipped, converted to parquet snappy.
4. **Projection**: parquet_total = parquet_historical + 10 * parquet_2024_yearly.

## Archetype ratios (parquet snappy / ZIP)

| Archetype | Sample ZIP | ZIP (MB) | CSV (MB) | Parquet (MB) | parquet/ZIP | csv/ZIP |
|---|---|---|---|---|---|---|
| company_yearly | `dfp_cia_aberta_2024.zip` | 12.8 | 284.3 | 10.9 | 0.856 | 22.258 |
| fund_monthly | `inf_diario_fi_202412.zip` | 10.8 | 47.9 | 18.4 | 1.709 | 4.445 |
| fii_yearly | `inf_mensal_fii_2024.zip` | 1.3 | 8.9 | 2.2 | 1.721 | 6.954 |
| company_static | `dfp_cia_aberta_2024.zip` | 12.8 | 284.3 | 10.9 | 0.856 | 22.258 |

## Per-dataset projection

| Scope | Category | Dataset | Archetype | Hist. yrs | ZIP total (MB) | ZIP 2024 (MB) | Parquet hist. (MB) | Parquet 2024/yr (MB) | **v1.0 total parquet (GB)** |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| v0.1 | CIA_ABERTA | CAD | company_static | 1 | 1.0 | 1.0 | 0.9 | 0.9 | **0.01** |
| v0.1 | CIA_ABERTA | DFP | company_yearly | 17 | 169.0 | 13.0 | 144.7 | 11.1 | **0.25** |
| v0.1 | CIA_ABERTA | FRE | company_yearly | 17 | 124.6 | 8.0 | 106.7 | 6.8 | **0.17** |
| v0.1 | CIA_ABERTA | ITR | company_yearly | 16 | 395.0 | 31.0 | 338.2 | 26.5 | **0.59** |
| v0.2 | CIA_ABERTA | CGVN | company_yearly | 9 | 30.1 | 4.0 | 25.7 | 3.4 | **0.06** |
| v0.2 | CIA_ABERTA | FCA | company_yearly | 17 | 6.2 | 0.4 | 5.3 | 0.3 | **0.01** |
| v0.2 | CIA_ABERTA | IPE | company_yearly | 24 | 28.6 | 2.0 | 24.5 | 1.7 | **0.04** |
| v0.2 | CIA_ABERTA | VLMO | company_yearly | 9 | 5.2 | 0.8 | 4.4 | 0.7 | **0.01** |
| v0.3 | CIA_ESTRANG | CAD | company_static | 1 | 0.0 | 0.0 | 0.0 | 0.0 | **0.00** |
| v0.3 | CIA_INCENT | CAD | company_static | 1 | 1.0 | 1.0 | 0.9 | 0.9 | **0.01** |
| v0.3 | CROWDFUNDING | CAD | company_static | 1 | 0.0 | 0.0 | 0.0 | 0.0 | **0.00** |
| v0.3 | OFERTA | DISTRIB | company_yearly | 1 | 5.0 | 5.0 | 4.3 | 4.3 | **0.05** |
| v0.4 | FI | BALANCETE | fund_monthly | 12 | 1398.0 | 168.0 | 2388.8 | 287.1 | **5.14** |
| v0.4 | FI | CDA | fund_monthly | 4 | 835.0 | 264.0 | 1426.8 | 451.1 | **5.80** |
| v0.4 | FI | COMPL | fund_monthly | 2 | 15.9 | 7.9 | 27.1 | 13.6 | **0.16** |
| v0.4 | FI | ENTREGA | fund_monthly | 2 | 336.0 | 168.0 | 574.1 | 287.1 | **3.36** |
| v0.4 | FI | EVENTUAL | fund_monthly | 22 | 357.0 | 32.0 | 610.0 | 54.7 | **1.13** |
| v0.4 | FI | EXTRATO | fund_monthly | 12 | 123.8 | 10.0 | 211.5 | 17.1 | **0.37** |
| v0.4 | FI | INF_DIARIO | fund_monthly | 6 | 655.0 | 130.0 | 1119.2 | 222.1 | **3.26** |
| v0.4 | FI | LAMINA | fund_monthly | 8 | 204.5 | 29.5 | 349.5 | 50.3 | **0.83** |
| v0.4 | FI | PERFIL_MENSAL | fund_monthly | 8 | 947.0 | 155.0 | 1618.2 | 264.9 | **4.17** |
| v0.5 | FII | DFIN | fii_yearly | 11 | 1.3 | 0.2 | 2.2 | 0.4 | **0.01** |
| v0.5 | FII | INF_ANUAL | fii_yearly | 10 | 16.3 | 3.0 | 28.0 | 5.2 | **0.08** |
| v0.5 | FII | INF_MENSAL | fii_yearly | 11 | 7.5 | 1.0 | 12.9 | 1.7 | **0.03** |
| v0.5 | FII | INF_TRIMESTRAL | fii_yearly | 11 | 14.5 | 2.0 | 25.0 | 3.4 | **0.06** |
| v0.6 | FIDC | INF_MENSAL | fii_yearly | 2 | 41.0 | 20.5 | 70.6 | 35.3 | **0.41** |
| v0.6+ | FIAGRO | INF_MENSAL | fii_yearly | 2 | 0.4 | 0.2 | 0.7 | 0.3 | **0.00** |
| v0.6+ | FIE | BALANCETE | fii_yearly | 3 | 2.2 | 0.8 | 3.8 | 1.3 | **0.02** |
| v0.6+ | FIE | BALANCO | fii_yearly | 16 | 0.7 | 0.0 | 1.1 | 0.1 | **0.00** |
| v0.6+ | FIP | INF_QUADRIMESTRAL | fii_yearly | 3 | 11.0 | 4.0 | 18.9 | 6.9 | **0.09** |
| v0.6+ | FIP | INF_TRIMESTRAL | fii_yearly | 14 | 27.1 | 1.9 | 46.7 | 3.3 | **0.08** |
| v0.6+ | SECURIT | DFIN_CRA | fii_yearly | 7 | 0.7 | 0.2 | 1.2 | 0.3 | **0.00** |
| v0.6+ | SECURIT | DFIN_CRI | fii_yearly | 8 | 2.7 | 0.5 | 4.6 | 0.9 | **0.01** |
| v0.6+ | SECURIT | INF_MENSAL_CRA | fii_yearly | 8 | 4.8 | 1.0 | 8.3 | 1.7 | **0.02** |
| v0.6+ | SECURIT | INF_MENSAL_CRI | fii_yearly | 8 | 26.8 | 5.0 | 46.1 | 8.6 | **0.13** |
| v0.6+ | SECURIT | INF_MENSAL_OTS | fii_yearly | 4 | 0.9 | 0.2 | 1.6 | 0.4 | **0.01** |

## Totals by scope

| Scope | Datasets | v1.0 total parquet (GB) |
|---|---:|---:|
| v0.1 | 4 | **1.02** |
| v0.2 | 4 | **0.12** |
| v0.3 | 4 | **0.06** |
| v0.4 | 9 | **24.22** |
| v0.5 | 4 | **0.17** |
| v0.6 | 1 | **0.41** |
| v0.6+ | 10 | **0.36** |
| **TOTAL** | 36 | **26.36** |

**Projected v1.0 mirror size: 26.36 GB (parquet snappy).**

## Assumptions and caveats

- Historical volume per dataset = sum of all years currently published by CVM.
- Future volume = 10 * size of 2024 (Sidney's heuristic; assumes flat universe).
- For datasets where the universe is growing (FI/INF_DIARIO, CDA, FIDC, FIAGRO),
  the projection is therefore **conservative** when applied to past years and
  **lower-bound** for future years. Recompute on next major scope review.
- Parquet ratio derives from 3 archetypes; outlier datasets (very wide tables,
  identifier-heavy schemas) may diverge.
- Participants (ADM_CART, AGENTE_AUTON, etc.) excluded as they are out of scope
  for v1.0 and consist of small static registers (estimated < 50 MB combined).

## Per-archetype contribution (sanity check)

| Archetype | Datasets | v1.0 total parquet (GB) |
|---|---:|---:|
| fund_monthly | 9 | 24.22 |
| company_yearly | 8 | 1.17 |
| fii_yearly | 15 | 0.95 |
| company_static | 4 | 0.02 |
