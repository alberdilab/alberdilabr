#' Validate a publication project
#'
#' Runs a series of structural, document, reproducibility and publishing checks
#' and reports the result of each one.
#'
#' Checks are grouped into categories:
#'
#' * **Structure** -- required files and directories, readable configuration,
#'   registered chapters that exist, chapter files that are not registered.
#' * **Documents** -- exactly one top-level heading per chapter, unique and
#'   well-formed heading identifiers, sequential numbering, duplicate knitr
#'   chunk labels, figures that cannot be cross-referenced.
#' * **Reproducibility** -- presence of `renv.lock` and whether the packages
#'   needed to render are recorded in it. No network access is performed.
#' * **Publishing** -- presence of the workflow, and agreement between the
#'   directory bookdown writes and the directory the workflow uploads.
#' * **Rendering** -- only when `render = TRUE`, a full build as an integration
#'   test.
#'
#' @param project Path to the publication project.
#' @param render Whether to render the project as a final check. This is slow
#'   and is skipped by default.
#' @param quiet Whether to suppress printing. The result is returned either way.
#'
#' @return An object of class `publication_check`: a data frame of checks with
#'   columns `category`, `status` (`"pass"`, `"warn"` or `"fail"`) and
#'   `message`. Returned invisibly when `quiet` is `FALSE`.
#' @export
#' @examples
#' \dontrun{
#' check_publication()
#' check_publication(render = TRUE)
#' }
check_publication <- function(project = ".", render = FALSE, quiet = FALSE) {
  project <- publication_root(project)
  config <- read_bookdown_config(project)

  results <- c(
    check_structure(project, config),
    check_documents(project, config),
    check_reproducibility(project),
    check_publishing(project, config)
  )
  if (isTRUE(render)) {
    results <- c(results, check_render(project))
  }

  out <- do.call(rbind, lapply(results, as.data.frame, stringsAsFactors = FALSE))
  rownames(out) <- NULL
  class(out) <- c("publication_check", class(out))
  attr(out, "project") <- project

  if (quiet) out else print(out)
}

# A check result is a category, a status and a message.
chk <- function(category, status, message) {
  list(category = category, status = status, message = message)
}
pass <- function(category, message) chk(category, "pass", message)
warn <- function(category, message) chk(category, "warn", message)
fail <- function(category, message) chk(category, "fail", message)

# Structure -------------------------------------------------------------------

check_structure <- function(project, config) {
  out <- list()
  has <- function(p) fs::file_exists(fs::path(project, p))
  has_dir <- function(p) fs::dir_exists(fs::path(project, p))

  for (f in c("index.Rmd", "_bookdown.yml", "_output.yml")) {
    out <- c(out, list(
      if (has(f)) pass("structure", sprintf("%s exists", f))
      else fail("structure", sprintf("%s is missing", f))
    ))
  }
  for (d in c("chapters", "R", "assets")) {
    out <- c(out, list(
      if (has_dir(d)) pass("structure", sprintf("%s/ exists", d))
      else warn("structure", sprintf("%s/ is missing", d))
    ))
  }

  chapters <- config_chapters(config)
  out <- c(out, list(
    pass("structure", sprintf(
      "%d chapter%s registered in _bookdown.yml",
      nrow(chapters), if (nrow(chapters) == 1) "" else "s"
    ))
  ))

  missing <- missing_chapter_files(project, config)
  out <- c(out, list(
    if (length(missing) == 0) pass("structure", "all registered files exist")
    else fail("structure", sprintf(
      "registered file%s missing from disk: %s",
      if (length(missing) == 1) "" else "s", paste(missing, collapse = ", ")
    ))
  ))

  # Files sitting in chapters/ that nothing references are silently excluded
  # from the book, which is a common and confusing mistake.
  if (has_dir("chapters")) {
    on_disk <- fs::path_rel(
      fs::dir_ls(fs::path(project, "chapters"), glob = "*.Rmd"),
      project
    )
    stray <- setdiff(as.character(on_disk), chapters$path)
    out <- c(out, list(
      if (length(stray) == 0) pass("structure", "no unregistered chapter files")
      else warn("structure", sprintf(
        "%s not registered in _bookdown.yml", paste(stray, collapse = ", ")
      ))
    ))
  }

  out <- c(out, list(
    if (!is.null(config$output_dir))
      pass("structure", sprintf("output_dir is %s/", config$output_dir))
    else warn("structure", "output_dir not set; bookdown will default to _book/")
  ))

  out <- c(out, list(
    if (has("references.bib")) pass("structure", "references.bib exists")
    else warn("structure", "references.bib is missing")
  ))

  css <- output_css(project)
  out <- c(out, lapply(css[!fs::file_exists(fs::path(project, css))], function(f) {
    fail("structure", sprintf("_output.yml references %s, which does not exist", f))
  }))

  out
}

output_css <- function(project) {
  path <- output_config_path(project)
  if (!fs::file_exists(path)) return(character(0))
  cfg <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  css <- cfg[["bookdown::bs4_book"]][["css"]]
  if (is.null(css)) character(0) else as.character(css)
}

# Documents -------------------------------------------------------------------

check_documents <- function(project, config) {
  out <- list()
  chapters <- config_chapters(config)
  present <- chapters[fs::file_exists(fs::path(project, chapters$path)), , drop = FALSE]
  if (nrow(present) == 0) {
    return(list(warn("documents", "no chapter files to inspect")))
  }

  scans <- lapply(fs::path(project, present$path), scan_rmd)
  names(scans) <- present$path

  # One level-1 heading per chapter: bookdown makes each one a separate page,
  # so two in a file silently splits the chapter.
  n_top <- vapply(scans, function(s) sum(s$headings$level == 1), integer(1))
  bad <- present$path[n_top != 1]
  out <- c(out, list(
    if (length(bad) == 0) pass("documents", "every chapter has exactly one top-level heading")
    else fail("documents", sprintf(
      "%s", paste(sprintf(
        "%s has %d top-level headings", bad, n_top[n_top != 1]
      ), collapse = "; ")
    ))
  ))

  ids <- unlist(lapply(scans, function(s) s$headings$id[s$headings$level == 1]))
  no_id <- present$path[vapply(scans, function(s) {
    top <- s$headings[s$headings$level == 1, , drop = FALSE]
    nrow(top) > 0 && any(is.na(top$id))
  }, logical(1))]
  out <- c(out, list(
    if (length(no_id) == 0) pass("documents", "every chapter heading has an identifier")
    else warn("documents", sprintf(
      "chapter heading without {#id}: %s", paste(no_id, collapse = ", ")
    ))
  ))

  ids <- ids[!is.na(ids)]
  dup <- unique(ids[duplicated(ids)])
  out <- c(out, list(
    if (length(dup) == 0) pass("documents", "chapter identifiers are unique")
    else fail("documents", sprintf(
      "duplicate chapter identifier%s: %s",
      if (length(dup) == 1) "" else "s", paste(dup, collapse = ", ")
    ))
  ))

  # The filename slug and the heading id are two halves of the same identity;
  # when they drift, links built from one stop matching the other.
  mismatch <- vapply(seq_len(nrow(present)), function(i) {
    top <- scans[[i]]$headings
    top <- top$id[top$level == 1]
    slug <- present$slug[i]
    length(top) == 1 && !is.na(top) && !is.na(slug) && top != slug
  }, logical(1))
  out <- c(out, list(
    if (!any(mismatch)) pass("documents", "filenames and heading identifiers agree")
    else warn("documents", sprintf(
      "heading id does not match filename slug: %s",
      paste(present$path[mismatch], collapse = ", ")
    ))
  ))

  expected <- pad_number(seq_len(nrow(present)))
  actual <- sub("-.*$", "", fs::path_file(present$path))
  out <- c(out, list(
    if (identical(expected, actual)) pass("documents", "chapter numbering is sequential")
    else warn("documents", sprintf(
      "chapter numbering is not sequential: expected %s, found %s",
      paste(expected, collapse = ", "), paste(actual, collapse = ", ")
    ))
  ))

  labels <- unlist(lapply(scans, function(s) s$chunk_labels))
  labels <- labels[!is.na(labels) & nzchar(labels)]
  dup_labels <- unique(labels[duplicated(labels)])
  out <- c(out, list(
    if (length(dup_labels) == 0) pass("documents", "knitr chunk labels are unique")
    else fail("documents", sprintf(
      "duplicate chunk label%s (knitr will error): %s",
      if (length(dup_labels) == 1) "" else "s", paste(dup_labels, collapse = ", ")
    ))
  ))

  unlabelled <- names(scans)[vapply(scans, function(s) s$unlabelled_figures > 0, logical(1))]
  out <- c(out, list(
    if (length(unlabelled) == 0) pass("documents", "all captioned figures can be cross-referenced")
    else warn("documents", sprintf(
      "%s contains an unlabelled figure (add a chunk label to use \\@ref)",
      paste(unlabelled, collapse = ", ")
    ))
  ))

  out
}

# A deliberately small, fence-aware scanner.
#
# A full CommonMark parser (via commonmark) would not help here: it does not
# know what a knitr chunk header is, so chunk labels and fig.cap would still
# need extracting by hand, and it would misread R comments inside chunks as
# ATX headings. Tracking fences is exactly the fragility that matters, and it
# is a few lines.
scan_rmd <- function(path) {
  lines <- read_lines_utf8(path)

  # Strip YAML front matter so that "# comment" style keys cannot look like
  # headings.
  if (length(lines) > 0 && grepl("^---\\s*$", lines[1])) {
    close_at <- which(grepl("^(---|\\.\\.\\.)\\s*$", lines))[-1]
    if (length(close_at) > 0) {
      lines <- lines[-seq_len(close_at[1])]
    }
  }

  fence <- NA_character_
  headings <- list()
  chunk_labels <- character(0)
  unlabelled_figures <- 0L

  for (i in seq_along(lines)) {
    line <- lines[i]
    open <- regmatches(line, regexpr("^\\s{0,3}(`{3,}|~{3,})", line))

    if (!is.na(fence)) {
      # Inside a fence: only its matching closer ends it.
      if (length(open) == 1 && startsWith(trimws(line), substr(fence, 1, 1)) &&
          nchar(trimws(open)) >= nchar(fence)) {
        fence <- NA_character_
      }
      next
    }

    if (length(open) == 1) {
      fence <- trimws(open)
      header <- regmatches(line, regexec("^\\s*`{3,}\\s*\\{([a-zA-Z0-9_]+)[ ,]*([^}]*)\\}", line))[[1]]
      if (length(header) == 3) {
        label <- trimws(sub("^([^,=]*)(,.*)?$", "\\1", header[3]))
        has_label <- nzchar(label) && !grepl("=", label)
        chunk_labels <- c(chunk_labels, if (has_label) label else NA_character_)
        if (!has_label && grepl("fig\\.cap\\s*=", header[3])) {
          unlabelled_figures <- unlabelled_figures + 1L
        }
      }
      next
    }

    m <- regmatches(line, regexec("^(#{1,6})\\s+(.*?)\\s*$", line))[[1]]
    if (length(m) == 3) {
      id <- regmatches(m[3], regexec("\\{#([^}[:space:]]+)", m[3]))[[1]]
      headings[[length(headings) + 1L]] <- data.frame(
        level = nchar(m[2]),
        text = trimws(sub("\\{.*$", "", m[3])),
        id = if (length(id) == 2) id[2] else NA_character_,
        line = i,
        stringsAsFactors = FALSE
      )
    }
  }

  list(
    headings = if (length(headings)) do.call(rbind, headings)
      else data.frame(level = integer(0), text = character(0),
                      id = character(0), line = integer(0),
                      stringsAsFactors = FALSE),
    chunk_labels = chunk_labels,
    unlabelled_figures = unlabelled_figures
  )
}

# Reproducibility -------------------------------------------------------------

# Packages a generated project needs in order to render. bs4_book pulls in
# bslib, downlit and xml2, which are easy to omit from a hand-written lockfile.
render_dependencies <- c("bookdown", "rmarkdown", "knitr", "bslib", "downlit", "xml2")

check_reproducibility <- function(project) {
  lock <- fs::path(project, "renv.lock")
  if (!fs::file_exists(lock)) {
    return(list(warn(
      "reproducibility",
      "renv.lock is missing; package versions are not pinned (run renv::init())"
    )))
  }
  out <- list(pass("reproducibility", "renv.lock is present"))

  parsed <- tryCatch(jsonlite_read(lock), error = function(e) NULL)
  if (is.null(parsed)) {
    return(c(out, list(fail("reproducibility", "renv.lock could not be parsed as JSON"))))
  }

  recorded <- names(parsed$Packages)
  missing <- setdiff(render_dependencies, recorded)
  out <- c(out, list(
    if (length(missing) == 0)
      pass("reproducibility", "renv.lock records every package needed to render")
    else warn("reproducibility", sprintf(
      "renv.lock does not record %s (run renv::snapshot())",
      paste(missing, collapse = ", ")
    ))
  ))

  if (fs::dir_exists(fs::path(project, "renv"))) {
    rprofile <- fs::path(project, ".Rprofile")
    activates <- fs::file_exists(rprofile) &&
      any(grepl("renv/activate.R", read_lines_utf8(rprofile), fixed = TRUE))
    out <- c(out, list(
      if (activates) pass("reproducibility", ".Rprofile activates renv")
      else warn("reproducibility", ".Rprofile does not source renv/activate.R")
    ))
  }
  out
}

# renv.lock is JSON. Rather than add a jsonlite dependency for one file, use
# renv's own reader when renv is available and fall back to a package-name
# scrape when it is not.
jsonlite_read <- function(path) {
  if (requireNamespace("renv", quietly = TRUE)) {
    lock <- renv::lockfile_read(path)
    return(list(Packages = lock$Packages))
  }
  lines <- read_lines_utf8(path)
  block <- grep('"Package"\\s*:', lines, value = TRUE)
  names <- gsub('^.*"Package"\\s*:\\s*"([^"]+)".*$', "\\1", block)
  list(Packages = stats::setNames(vector("list", length(names)), names))
}

# Publishing ------------------------------------------------------------------

check_publishing <- function(project, config) {
  workflow <- fs::path(project, ".github", "workflows", "publish.yml")
  if (!fs::file_exists(workflow)) {
    return(list(warn(
      "publishing",
      ".github/workflows/publish.yml is missing (run use_github_publication())"
    )))
  }
  out <- list(pass("publishing", "GitHub publishing workflow exists"))

  output_dir <- config$output_dir %||% "_book"
  uploaded <- workflow_artifact_path(workflow)
  out <- c(out, list(
    if (is.na(uploaded))
      warn("publishing", "could not determine which directory the workflow uploads")
    else if (identical(trimws(uploaded), output_dir))
      pass("publishing", sprintf("workflow uploads %s/, matching output_dir", uploaded))
    else fail("publishing", sprintf(
      "workflow uploads %s/ but bookdown writes to %s/", uploaded, output_dir
    ))
  ))

  gitignore <- fs::path(project, ".gitignore")
  ignored <- fs::file_exists(gitignore) &&
    any(grepl(sprintf("^/?%s/?$", output_dir), trimws(read_lines_utf8(gitignore))))
  out <- c(out, list(
    if (ignored) pass("publishing", sprintf("%s/ is not tracked in Git", output_dir))
    else warn("publishing", sprintf(
      "%s/ is not listed in .gitignore; rendered HTML may be committed", output_dir
    ))
  ))
  out
}

# YAML 1.1 turns the workflow's `on:` key into TRUE, so the file is scanned as
# text rather than parsed: we only need the artifact path.
workflow_artifact_path <- function(path) {
  lines <- read_lines_utf8(path)
  at <- grep("upload-pages-artifact", lines, fixed = TRUE)
  if (length(at) == 0) return(NA_character_)
  tail_lines <- lines[seq(at[1], min(at[1] + 6L, length(lines)))]
  hit <- grep("^\\s*path:\\s*", tail_lines, value = TRUE)
  if (length(hit) == 0) return(NA_character_)
  value <- sub("^\\s*path:\\s*", "", hit[1])
  gsub('^["\']|["\']$|/$', "", trimws(value))
}

# Rendering -------------------------------------------------------------------

check_render <- function(project) {
  result <- tryCatch(
    {
      render_publication(project, quiet = TRUE)
      NULL
    },
    error = function(e) conditionMessage(e)
  )
  if (!is.null(result)) {
    return(list(fail("rendering", sprintf("render failed: %s", result))))
  }
  config <- read_bookdown_config(project)
  index <- fs::path(project, config$output_dir %||% "_book", "index.html")
  list(
    if (fs::file_exists(index)) pass("rendering", "project renders successfully")
    else fail("rendering", "render produced no index.html")
  )
}

# Printing --------------------------------------------------------------------

#' @export
print.publication_check <- function(x, ...) {
  project <- attr(x, "project")
  cli::cli_h1("Publication check")
  cli::cli_text("{.path {project}}")

  for (category in unique(x$category)) {
    rows <- x[x$category == category, , drop = FALSE]
    cli::cli_h2(tools::toTitleCase(category))
    for (i in seq_len(nrow(rows))) {
      # Interpolate the message as a value, never as a format string: check
      # messages legitimately contain braces (heading ids, chunk options) and
      # must not be re-evaluated by cli.
      msg <- rows$message[i]
      switch(rows$status[i],
        pass = cli::cli_alert_success("{msg}"),
        warn = cli::cli_alert_warning("{msg}"),
        fail = cli::cli_alert_danger("{msg}")
      )
    }
  }

  n_fail <- sum(x$status == "fail")
  n_warn <- sum(x$status == "warn")
  cli::cli_rule()
  if (n_fail == 0 && n_warn == 0) {
    cli::cli_alert_success("{nrow(x)} check{?s} passed.")
  } else {
    cli::cli_text(
      "{sum(x$status == 'pass')} passed, {n_warn} warning{?s}, {n_fail} failure{?s}."
    )
  }
  invisible(x)
}
