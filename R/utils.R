#' @keywords internal
#' @importFrom rlang %||%
NULL

# Error helpers ---------------------------------------------------------------

# All package errors carry the class "alberdilabr_error" so callers (and tests)
# can catch them as a group, plus a specific subclass.
# .envir must be the caller's frame, not this wrapper's: cli interpolates the
# message where it is written, and every call site refers to its own locals.
pub_abort <- function(message,
                      class = NULL,
                      ...,
                      call = rlang::caller_env(),
                      .envir = rlang::caller_env()) {
  cli::cli_abort(
    message,
    class = c(class, "alberdilabr_error"),
    ...,
    call = call,
    .envir = .envir
  )
}

# Suggested-package gate. Keeps bookdown/renv/servr out of Imports while still
# failing with an actionable message at the point of use.
check_suggested <- function(pkg, reason, call = rlang::caller_env()) {
  # `pkg` and `reason` are locals of this function, so interpolate here.
  if (!requireNamespace(pkg, quietly = TRUE)) {
    pub_abort(
      c(
        "The {.pkg {pkg}} package is required to {reason}.",
        i = 'Install it with {.run install.packages("{pkg}")}.'
      ),
      class = "alberdilabr_error_missing_package",
      call = call
    )
  }
  invisible(TRUE)
}

# Filesystem ------------------------------------------------------------------

# Write text atomically: build the file alongside its destination, then rename.
# rename() within a directory is atomic on every platform we target, so a
# reader never observes a half-written _bookdown.yml.
write_lines_atomic <- function(lines, path) {
  path <- fs::path_abs(path)
  fs::dir_create(fs::path_dir(path))
  tmp <- fs::file_temp(tmp_dir = fs::path_dir(path), ext = "tmp")
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)

  con <- file(tmp, open = "wb", encoding = "UTF-8")
  writeLines(enc2utf8(lines), con, useBytes = TRUE)
  close(con)

  fs::file_move(tmp, path)
  invisible(path)
}

# Read bytes and mark them as UTF-8 rather than asking the connection to
# transcode. Templates are UTF-8 on disk, but R sessions frequently run under a
# C locale, where transcoding to native would mangle non-ASCII characters and
# warn about "invalid input".
read_lines_utf8 <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  Encoding(lines) <- "UTF-8"
  lines
}

# Project discovery -----------------------------------------------------------

#' Locate the root of a publication project
#'
#' Walks up from `path` looking for a directory that contains `_bookdown.yml`.
#'
#' @param path A path inside a publication project. Defaults to the working
#'   directory.
#' @return The absolute path to the project root, as a character string.
#' @export
#' @examples
#' \dontrun{
#' publication_root()
#' }
publication_root <- function(path = ".") {
  start <- fs::path_abs(path)
  if (!fs::dir_exists(start) && fs::file_exists(start)) {
    start <- fs::path_dir(start)
  }
  current <- start
  repeat {
    if (fs::file_exists(fs::path(current, "_bookdown.yml"))) {
      return(as.character(current))
    }
    parent <- fs::path_dir(current)
    if (parent == current) break
    current <- parent
  }
  pub_abort(
    c(
      "Could not find a publication project at or above {.path {start}}.",
      i = "A publication project is a directory containing {.file _bookdown.yml}.",
      i = "Create one with {.fn create_publication}."
    ),
    class = "alberdilabr_error_no_project"
  )
}

# Formatting ------------------------------------------------------------------

# Chapter files are numbered 01, 02, ... and stay two-digit until they cannot.
pad_number <- function(n) {
  ifelse(n < 100, sprintf("%02d", n), as.character(n))
}
