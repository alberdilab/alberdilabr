# Slugs are the stable identity of a chapter. They appear in three places that
# must agree: the filename (`NN-<slug>.Rmd`), the `rmd_files` entry in
# `_bookdown.yml`, and the heading identifier (`# Title {#<slug>}`) that
# bookdown turns into the page anchor and cross-reference target.

#' Convert a title to a filesystem- and URL-safe slug
#'
#' @param x A character vector of titles.
#' @return A character vector of slugs: lowercase ASCII, words separated by
#'   single hyphens.
#' @export
#' @examples
#' make_slug("Sensitivity Analysis")
#' make_slug("Results & Discussion")
make_slug <- function(x) {
  if (!is.character(x)) {
    pub_abort(
      "{.arg x} must be a character vector, not {.obj_type_friendly {x}}.",
      class = "alberdilabr_error_type"
    )
  }
  # Transliterate accented characters rather than dropping them, so that
  # an accented "Analisis" becomes "analisis" and not "anlisis".
  out <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  out <- ifelse(is.na(out), x, out)
  out <- tolower(out)
  out <- gsub("['\u2019]", "", out)
  out <- gsub("[^a-z0-9]+", "-", out)
  out <- gsub("^-+|-+$", "", out)
  out
}

# A slug has to survive being a filename, a YAML scalar and an HTML anchor.
validate_slug <- function(slug, arg = "slug", call = rlang::caller_env()) {
  if (!rlang::is_string(slug) || !nzchar(slug)) {
    pub_abort(
      c(
        "{.arg {arg}} must be a single non-empty string.",
        x = "Got {.val {slug}}."
      ),
      class = "alberdilabr_error_slug",
      call = call
    )
  }
  if (!grepl("^[a-z0-9]+(-[a-z0-9]+)*$", slug)) {
    pub_abort(
      c(
        "{.arg {arg}} must be lowercase alphanumeric words separated by single hyphens.",
        x = "Got {.val {slug}}.",
        i = "Try {.val {make_slug(slug)}}."
      ),
      class = "alberdilabr_error_slug",
      call = call
    )
  }
  invisible(slug)
}

# Path <-> chapter identity ---------------------------------------------------

chapter_filename <- function(number, slug) {
  paste0(pad_number(number), "-", slug, ".Rmd")
}

# Chapters live in the project root, alongside index.Rmd: they are the
# documents the author works on, and bookdown reads them from there without
# further configuration.
chapter_path <- function(number, slug) {
  chapter_filename(number, slug)
}

# Returns NA for paths that do not follow the `NN-slug.Rmd` convention (for
# example a hand-added `notes.Rmd`), which lets check_publication() report them
# rather than crash on them.
parse_chapter_path <- function(path) {
  base <- fs::path_file(path)
  m <- regmatches(base, regexec("^([0-9]+)-(.+)\\.Rmd$", base, ignore.case = TRUE))
  vapply(m, function(x) if (length(x) == 3L) x[[3]] else NA_character_, character(1))
}

parse_chapter_number <- function(path) {
  base <- fs::path_file(path)
  m <- regmatches(base, regexec("^([0-9]+)-(.+)\\.Rmd$", base, ignore.case = TRUE))
  vapply(m, function(x) if (length(x) == 3L) as.integer(x[[2]]) else NA_integer_, integer(1))
}
