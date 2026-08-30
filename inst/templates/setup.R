# Project-wide setup, sourced from index.Rmd before any chapter is knitted.
# Chapters can source it directly too: source("alberdilabr/setup.R").
#
# Put library() calls, ggplot themes, options and small helper functions here so
# that every chapter starts from the same state.

options(
  digits = 3,
  scipen = 999,
  knitr.kable.NA = ""
)

# Example: attach the packages your analysis needs.
# library(ggplot2)
# library(dplyr)

# Example: a shared plot theme.
# theme_set(theme_minimal(base_size = 12))
