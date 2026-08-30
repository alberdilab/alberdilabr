# Template rendering.
#
# We deliberately do not use usethis::use_template(). usethis resolves paths
# against a global "active project", which is the wrong model for a function
# whose whole job is to populate a directory that is not the active project
# yet. The renderer below is explicit about its destination instead.
#
# whisker (mustache) is used rather than glue because templates contain knitr
# chunk headers such as ```{r setup} -- brace-delimited interpolation would
# have to escape every one of them.

template_path <- function(...) {
  requested <- fs::path(...)
  path <- system.file("templates", ..., package = "alberdilabr")
  if (!nzchar(path)) {
    pub_abort(
      "Internal error: missing package template {.file {requested}}.",
      class = "alberdilabr_error_missing_template"
    )
  }
  path
}

# Render a package template to a destination inside `project`.
use_template <- function(template,
                         save_as = template,
                         data = list(),
                         project = ".",
                         overwrite = FALSE) {
  dest <- fs::path(project, save_as)
  if (fs::file_exists(dest) && !overwrite) {
    pub_abort(
      c(
        "Refusing to overwrite {.path {save_as}}.",
        i = "It already exists in {.path {project}}."
      ),
      class = "alberdilabr_error_exists"
    )
  }
  body <- read_lines_utf8(template_path(template))
  rendered <- whisker::whisker.render(paste(body, collapse = "\n"), data)
  write_lines_atomic(strsplit(rendered, "\n", fixed = TRUE)[[1]], dest)
  invisible(dest)
}

# Chapter bodies are rendered without touching disk so that add_chapter() can
# validate everything before it creates any file.
#
# Templates receive `title`, `slug` and `anchor`. `anchor` is the ready-made
# heading attribute "{#slug}": see the note on whisker_hazard() for why
# templates must not build it themselves.
render_chapter_template <- function(template, data) {
  file <- paste0(template, ".Rmd")
  candidate <- system.file("templates", "chapters", file, package = "alberdilabr")
  if (!nzchar(candidate)) {
    pub_abort(
      c(
        "Unknown chapter template {.val {template}}.",
        i = "Available templates: {.val {chapter_templates()}}."
      ),
      class = "alberdilabr_error_unknown_template"
    )
  }
  body <- read_lines_utf8(candidate)
  whisker_hazard(body, candidate)

  data$anchor <- paste0("{#", data$slug, "}")
  rendered <- whisker::whisker.render(paste(body, collapse = "\n"), data)
  lines <- strsplit(rendered, "\n", fixed = TRUE)[[1]]

  # The rendered chapter must carry its own anchor, or every cross-reference to
  # it will dangle. Catch it here rather than at render time.
  if (!any(grepl(data$anchor, lines, fixed = TRUE))) {
    pub_abort(
      c(
        "Template {.val {template}} produced no {.code {data$anchor}} heading anchor.",
        i = "A chapter template must include {.code {{{anchor}}}} on its top-level heading."
      ),
      class = "alberdilabr_error_bad_template"
    )
  }
  lines
}

# whisker silently discards a template tag whose closing delimiter is
# immediately followed by "}", so `{#{{{slug}}}}` renders as `{#`. That bites
# exactly where an R Markdown author would reach for it -- heading attributes
# and chunk headers -- and it fails quietly, so refuse the template instead.
whisker_hazard <- function(lines, path) {
  bad <- grep("\\}\\}\\}\\}|%>\\}", lines)
  if (length(bad) == 0) {
    return(invisible(TRUE))
  }
  pub_abort(
    c(
      "Template {.file {path}} has a placeholder immediately before {.code \u007d}.",
      x = "Line {bad[1]}: {.code {lines[bad[1]]}}",
      i = "whisker drops such placeholders silently. Use the {.code anchor} \\
           variable for heading attributes, or put a space before the {.code \u007d}."
    ),
    class = "alberdilabr_error_bad_template"
  )
}

#' Chapter templates shipped with the package
#'
#' @return A character vector of template names accepted by the `template`
#'   argument of [add_chapter()].
#' @export
#' @examples
#' chapter_templates()
chapter_templates <- function() {
  dir <- system.file("templates", "chapters", package = "alberdilabr")
  if (!nzchar(dir)) {
    return(character(0))
  }
  sort(fs::path_ext_remove(fs::path_file(fs::dir_ls(dir, glob = "*.Rmd"))))
}
