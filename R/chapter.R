# Chapter management.
#
# Every mutating operation follows the same order:
#   1. read and validate the current state
#   2. compute the complete intended new state in memory
#   3. touch the filesystem
#   4. write _bookdown.yml last, atomically
#   5. on failure, undo step 3
#
# _bookdown.yml is written last because it is the file that defines the
# project. A crash before step 4 leaves an unreferenced stray file, which
# check_publication() reports; a crash during step 4 cannot leave a truncated
# config, because the write is a rename.

#' Add a chapter
#'
#' Creates a numbered chapter file from a template and registers it in
#' `_bookdown.yml`.
#'
#' @param title Chapter title, used for the top-level heading.
#' @param slug Identifier used for the filename and the heading anchor.
#'   Defaults to a slugified `title`. Must be unique within the project.
#' @param after Where to insert the chapter. `NULL` (the default) appends it at
#'   the end. Otherwise the slug, filename or path of an existing chapter to
#'   insert after, or `0` to insert first.
#' @param template Name of a chapter template, one of [chapter_templates()].
#' @param project Path to the publication project.
#' @param quiet Whether to suppress the success message.
#'
#' @return The path of the created chapter, relative to the project root,
#'   invisibly.
#' @export
#' @examples
#' \dontrun{
#' add_chapter("Sensitivity analysis")
#' add_chapter("Study design", after = "introduction", template = "methods")
#' }
add_chapter <- function(title,
                        slug = NULL,
                        after = NULL,
                        template = "chapter",
                        project = ".",
                        quiet = FALSE) {
  if (!rlang::is_string(title) || !nzchar(trimws(title))) {
    pub_abort(
      "{.arg title} must be a single non-empty string.",
      class = "alberdilabr_error_type"
    )
  }
  project <- publication_root(project)
  config <- read_bookdown_config(project)

  slug <- slug %||% make_slug(title)
  validate_slug(slug)
  existing <- config_chapters(config)

  if (slug %in% existing$slug) {
    conflict <- existing$path[match(slug, existing$slug)]
    pub_abort(
      c(
        "Cannot add chapter {.val {slug}}: it is already registered.",
        x = "{.file {conflict}} uses that identifier.",
        i = "Pass a different {.arg slug}."
      ),
      class = "alberdilabr_error_duplicate_chapter"
    )
  }

  position <- resolve_insert_position(config, after)
  number <- position + 1L
  new_path <- chapter_path(number, slug)

  if (fs::file_exists(fs::path(project, new_path))) {
    pub_abort(
      c(
        "Cannot add chapter {.val {slug}}: {.file {new_path}} already exists.",
        i = "Remove the file, or choose a different {.arg slug}."
      ),
      class = "alberdilabr_error_exists"
    )
  }

  # Render the body before writing anything, so an unknown template fails
  # without having created a file.
  body <- render_chapter_template(template, list(title = title, slug = slug))

  files <- config_rmd_files(config)
  chapter_files <- append(existing$path, new_path, after = position)

  created <- character(0)
  success <- FALSE
  on.exit(
    if (!success) for (f in created) if (fs::file_exists(f)) fs::file_delete(f),
    add = TRUE
  )

  target <- fs::path(project, new_path)
  write_lines_atomic(body, target)
  created <- c(created, target)

  renamed <- renumber_chapter_files(project, chapter_files)
  created <- c(created, renamed$created)

  config$rmd_files <- c(index_entry(files), renamed$paths)
  write_bookdown_config(project, config)
  success <- TRUE

  final <- renamed$paths[position + 1L]
  if (!quiet) {
    cli::cli_alert_success("Added chapter {.val {slug}} at {.file {final}}.")
  }
  invisible(final)
}

#' Remove a chapter
#'
#' Unregisters a chapter and optionally deletes its file, renumbering the
#' chapters that follow.
#'
#' @param chapter Slug, filename or path of the chapter to remove.
#' @param delete_file Whether to delete the `.Rmd` file. `FALSE` unregisters it
#'   but leaves it on disk.
#' @inheritParams add_chapter
#'
#' @return The path of the removed chapter, invisibly.
#' @export
#' @examples
#' \dontrun{
#' remove_chapter("sensitivity-analysis")
#' remove_chapter("discussion", delete_file = FALSE)
#' }
remove_chapter <- function(chapter,
                           delete_file = TRUE,
                           project = ".",
                           quiet = FALSE) {
  project <- publication_root(project)
  config <- read_bookdown_config(project)
  target <- resolve_chapter(config, chapter)

  existing <- config_chapters(config)
  remaining <- existing$path[-target$position]
  old_path <- fs::path(project, target$path)

  # Move the file aside rather than deleting it outright, so that a failure
  # during renumbering can put it back.
  parked <- NULL
  success <- FALSE
  on.exit(
    if (!success && !is.null(parked) && fs::file_exists(parked)) {
      fs::file_move(parked, old_path)
    },
    add = TRUE
  )

  if (fs::file_exists(old_path)) {
    parked <- fs::file_temp(ext = "Rmd")
    fs::file_move(old_path, parked)
  }

  renamed <- renumber_chapter_files(project, remaining)
  config$rmd_files <- c(index_entry(config_rmd_files(config)), renamed$paths)
  write_bookdown_config(project, config)
  success <- TRUE

  if (!is.null(parked) && fs::file_exists(parked)) {
    if (isTRUE(delete_file)) {
      fs::file_delete(parked)
    } else {
      fs::file_move(parked, fs::path(project, fs::path_file(target$path)))
    }
  }

  if (!quiet) {
    cli::cli_alert_success(
      "Removed chapter {.val {target$slug}}{if (delete_file) '' else ' (file kept)'}."
    )
  }
  invisible(target$path)
}

#' Move a chapter
#'
#' Changes a chapter's position in the reading order and renumbers the affected
#' files.
#'
#' @param chapter Slug, filename or path of the chapter to move.
#' @param after Slug, filename or path of the chapter it should follow, or `0`
#'   to move it to the front.
#' @inheritParams add_chapter
#'
#' @return The chapter's new path, invisibly.
#' @export
#' @examples
#' \dontrun{
#' move_chapter("discussion", after = "methods")
#' move_chapter("summary", after = 0)
#' }
move_chapter <- function(chapter, after, project = ".", quiet = FALSE) {
  project <- publication_root(project)
  config <- read_bookdown_config(project)
  target <- resolve_chapter(config, chapter)

  existing <- config_chapters(config)
  without <- existing$path[-target$position]

  # Resolve `after` against the order the chapter is being removed from, so
  # that move_chapter("a", after = "b") means "directly after b" regardless of
  # which way the chapter is travelling.
  probe <- config
  probe$rmd_files <- c(index_entry(config_rmd_files(config)), without)
  position <- resolve_insert_position(probe, after)

  reordered <- append(without, target$path, after = position)
  if (identical(reordered, existing$path)) {
    if (!quiet) {
      cli::cli_alert_info("Chapter {.val {target$slug}} is already in that position.")
    }
    return(invisible(target$path))
  }

  renamed <- renumber_chapter_files(project, reordered)
  config$rmd_files <- c(index_entry(config_rmd_files(config)), renamed$paths)
  write_bookdown_config(project, config)

  final <- renamed$paths[position + 1L]
  if (!quiet) {
    cli::cli_alert_success("Moved chapter {.val {target$slug}} to {.file {final}}.")
  }
  invisible(final)
}

# Helpers ---------------------------------------------------------------------

# index.Rmd always leads rmd_files; bookdown treats the first entry as the
# landing page regardless of its name, but keeping it explicit and first makes
# the file readable.
index_entry <- function(files) {
  if ("index.Rmd" %in% files) "index.Rmd" else character(0)
}

# Translate `after` into a 0-based insertion offset for append().
resolve_insert_position <- function(config, after, call = rlang::caller_env()) {
  chapters <- config_chapters(config)
  if (is.null(after)) {
    return(nrow(chapters))
  }
  if (is.numeric(after)) {
    if (length(after) != 1 || is.na(after) || after < 0 || after > nrow(chapters)) {
      pub_abort(
        c(
          "{.arg after} must be between {.val {0}} and {.val {nrow(chapters)}}.",
          x = "Got {.val {after}}."
        ),
        class = "alberdilabr_error_position",
        call = call
      )
    }
    return(as.integer(after))
  }
  resolve_chapter(config, after, call = call)$position
}

# Rename chapter files so their numeric prefixes match `paths` order. Renaming
# goes via temporary names first, because a reorder such as 01 -> 02, 02 -> 01
# would otherwise have the two files collide mid-way.
renumber_chapter_files <- function(project, paths) {
  if (length(paths) == 0) {
    return(list(paths = character(0), created = character(0)))
  }
  slugs <- parse_chapter_path(paths)
  wanted <- ifelse(
    is.na(slugs),
    paths,
    chapter_path(seq_along(paths), slugs)
  )

  changing <- which(wanted != paths)
  if (length(changing) == 0) {
    return(list(paths = wanted, created = character(0)))
  }

  staged <- character(0)
  for (i in changing) {
    from <- fs::path(project, paths[i])
    if (!fs::file_exists(from)) {
      # Nothing to move: the file is missing, which check_publication() reports.
      staged <- c(staged, NA_character_)
      next
    }
    tmp <- fs::file_temp(tmp_dir = project, ext = "tmp")
    fs::file_move(from, tmp)
    staged <- c(staged, as.character(tmp))
  }

  created <- character(0)
  for (j in seq_along(changing)) {
    if (is.na(staged[j])) next
    to <- fs::path(project, wanted[changing[j]])
    fs::file_move(staged[j], to)
    created <- c(created, as.character(to))
  }

  list(paths = wanted, created = created)
}
