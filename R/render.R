#' Render a publication
#'
#' Renders the project with `bookdown::render_book()` into the `output_dir`
#' declared in `_bookdown.yml` (`_site/` by default).
#'
#' Bookdown's own errors are not caught or reformatted: a failing chunk should
#' surface with its original message and traceback.
#'
#' @param project Path to the publication project.
#' @param output_format Passed to `bookdown::render_book()`. `NULL` uses the
#'   formats declared in `_output.yml`.
#' @param quiet Whether to suppress knitr's progress output.
#' @param ... Further arguments passed to `bookdown::render_book()`.
#'
#' @return The absolute path to the rendered site directory, invisibly.
#' @export
#' @examples
#' \dontrun{
#' render_publication()
#' }
render_publication <- function(project = ".",
                               output_format = NULL,
                               quiet = FALSE,
                               ...) {
  check_suggested("bookdown", "render a publication")
  project <- publication_root(project)
  config <- read_bookdown_config(project)
  output_dir <- config$output_dir %||% "_book"

  missing <- missing_chapter_files(project, config)
  if (length(missing) > 0) {
    pub_abort(
      c(
        "Cannot render: {length(missing)} registered file{?s} {?is/are} missing.",
        x = "{.file {missing}}",
        i = "Run {.run alberdilabr::check_publication()} for the full picture."
      ),
      class = "alberdilabr_error_missing_files"
    )
  }

  cli::cli_alert_info("Rendering {.path {project}} into {.path {output_dir}}{cli::symbol$ellipsis}")

  old <- setwd(project)
  on.exit(setwd(old), add = TRUE)

  bookdown::render_book(
    input = "index.Rmd",
    output_format = output_format,
    quiet = quiet,
    ...
  )

  site <- fs::path(project, output_dir)
  index <- fs::path(site, "index.html")
  if (fs::file_exists(index)) {
    cli::cli_alert_success("Rendered {.path {fs::path(output_dir, 'index.html')}}.")
  } else {
    cli::cli_alert_warning(
      "Render finished but {.file {fs::path(output_dir, 'index.html')}} was not produced."
    )
  }
  invisible(as.character(site))
}

#' Preview a publication locally
#'
#' Renders the project and serves it on a local web server that rebuilds and
#' reloads the page whenever a source file changes.
#'
#' This wraps `bookdown::serve_book()`, which is bookdown's own live-preview
#' server (built on \pkg{servr}). It re-renders only the chapter you edit, which
#' makes it much faster than a full [render_publication()] for day-to-day
#' writing, at the cost of occasionally stale cross-references. Do a full render
#' before publishing.
#'
#' @param project Path to the publication project.
#' @param port Port to serve on. `NULL` lets \pkg{servr} choose a free one.
#' @param browse Whether to open a browser window.
#' @param ... Further arguments passed to `bookdown::serve_book()`.
#'
#' @return The value returned by `bookdown::serve_book()`, invisibly.
#' @export
#' @examples
#' \dontrun{
#' preview_publication()
#' }
preview_publication <- function(project = ".",
                                port = NULL,
                                browse = rlang::is_interactive(),
                                ...) {
  check_suggested("bookdown", "preview a publication")
  check_suggested("servr", "serve a live preview")
  project <- publication_root(project)
  config <- read_bookdown_config(project)
  output_dir <- config$output_dir %||% "_book"

  args <- list(
    dir = project,
    output_dir = output_dir,
    preview = TRUE,
    in_session = TRUE,
    daemon = TRUE,
    browse = browse,
    ...
  )
  if (!is.null(port)) {
    args$port <- port
  }

  cli::cli_alert_info(
    "Starting live preview. Stop it with {.run servr::daemon_stop()}."
  )
  invisible(do.call(bookdown::serve_book, args))
}

# Shared with check_publication(): registered files that are not on disk.
missing_chapter_files <- function(project, config) {
  files <- config_rmd_files(config)
  files[!fs::file_exists(fs::path(project, files))]
}
