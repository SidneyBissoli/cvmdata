# Format a CNPJ vector with the canonical punctuation

Inverse of
[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md).
Takes one or more CNPJs in any format (digits-only or already
punctuated) and returns them as `"NN.NNN.NNN/NNNN-NN"`. Useful when
cross-referencing data from external bases (Receita Federal, DATASUS,
IBGE, eSocial) against the punctuated `cnpj_cia` column the package
preserves from CVM.

## Usage

``` r
cnpj_format(x)
```

## Arguments

- x:

  Character vector of CNPJs (digits-only or punctuated).

## Value

Character vector of the same length as `x`, formatted as
`"NN.NNN.NNN/NNNN-NN"`. `NA_character_` where the input is NA or has a
non-14-digit body.

## Details

`NA` is preserved. Inputs whose digit-only form is not exactly 14
characters return `NA_character_` and a single warning of class
`cvmdata_warn` listing the offending positions; downstream code can
decide whether to filter the NAs or escalate.

## See also

[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)

Other utilities:
[`cnpj_clean()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_clean.md)

## Examples

``` r
cnpj_format("12345678000190")
#> [1] "12.345.678/0001-90"
cnpj_format(c("12345678000190", NA, "12.345.678/0001-90"))
#> [1] "12.345.678/0001-90" NA                   "12.345.678/0001-90"
```
