# Strip punctuation from a CNPJ vector

Returns the 14-digit form of one or more Brazilian taxpayer-id numbers
(CNPJ). The package stores `cnpj_cia` with punctuation as published by
CVM (`"12.345.678/0001-90"`); this helper produces the digits-only form
used by external bases such as Receita Federal, DATASUS, IBGE and
eSocial.

## Usage

``` r
cnpj_clean(x)
```

## Arguments

- x:

  Character vector of CNPJs in any format.

## Value

Character vector of the same length as `x`, with only the digits
retained.

## Details

Non-digit characters are removed; `NA` is preserved. No length or
check-digit validation is performed in v0.1; that may be added later.

## See also

Other utilities:
[`cnpj_format()`](https://sidneybissoli.github.io/cvmdata/reference/cnpj_format.md)

## Examples

``` r
cnpj_clean("12.345.678/0001-90")
#> [1] "12345678000190"
cnpj_clean(c("12.345.678/0001-90", NA, "99999999000191"))
#> [1] "12345678000190" NA               "99999999000191"
```
