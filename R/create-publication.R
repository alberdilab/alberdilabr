#' Create a publication project
#'
#' Scaffolds a complete, immediately renderable
#' [bookdown](https://bookdown.org) publication project: R Markdown sources,
#' chapter ordering, HTML output configuration, custom CSS, a bibliography, a
#' Git repository, an optional [renv] lockfile, and a GitHub Actions workflow
#' that deploys the rendered site to GitHub Pages.
#'
#' The generated project is a standard bookdown project. It renders with
#' `bookdown::render_book()` alone and does not need this package at render
#' time.
#'
#' @param path Directory to create the project in. Defaults to the working
#'   directory, since R is normally run from the root of the repository that
#'   will hold the publication. The directory may already exist and already
#'   contain files -- a `.git/`, a licence, whatever the repository came with
#'   -- as long as none of them are files this function itself writes.
#' @param title Title of the publication. Defaults to a title-cased version of
#'   the directory name.
#' @param author Author name. Defaults to `getOption("usethis.full_name")`, then
#'   to the `user.name` recorded in the local Git configuration.
#' @param description One-line description, used in the site metadata and
#'   `README.md`.
#' @param chapters Character vector of starter chapter titles, in reading order.
#'   A title whose slug matches one of [chapter_templates()] uses that template;
#'   any other title uses the generic `"chapter"` template. Pass
#'   `character(0)` to create no starter chapters.
#' @param renv Whether to initialise a [renv] lockfile. `TRUE` (the default)
#'   runs `renv::init()` in a separate R process, which installs the project's
#'   dependencies into a private library and can take several minutes. `FALSE`
#'   skips it and generates a workflow that installs packages unpinned.
#' @param git Whether to initialise a Git repository and make an initial commit.
#' @param github_actions Whether to write `.github/workflows/publish.yml`.
#' @param branch Name of the branch that triggers deployment.
#' @param repo Optional `"owner/name"` GitHub repository, used to add
#'   edit/source links to every page. `NULL` omits the links.
#' @param primary_color Accent colour for the bs4 theme and the generated CSS.
#' @param open Whether to open the new project in RStudio when available.
#'
#' @return The absolute path to the created project, invisibly.
#' @export
#' @examples
#' \dontrun{
#' create_publication(
#'   path = "my-analysis",
#'   title = "My Analysis",
#'   author = "Jane Doe"
#' )
#' }
create_publication <- function(path = ".",
                               title = NULL,
                               author = NULL,
                               description = "A reproducible publication.",
                               chapters = c("Introduction", "Methods", "Results", "Discussion"),
                               renv = TRUE,
                               git = TRUE,
                               github_actions = TRUE,
                               branch = "main",
                               repo = NULL,
                               primary_color = "#0068D9",
                               open = rlang::is_interactive()) {
  path <- fs::path_abs(path)
  name <- fs::path_file(path)
  title <- title %||% default_title(name)
  author <- author %||% default_author()
  chapters <- as.character(chapters)

  files <- publication_files(name, chapters, github_actions)
  check_target_directory(path, files)

  if (!rlang::is_string(branch) || !nzchar(branch)) {
    pub_abort(
      "{.arg branch} must be a single non-empty string.",
      class = "alberdilabr_error_type"
    )
  }

  # Everything below either completes or leaves no trace. A project created in
  # its own new directory is removed wholesale; one scaffolded into a directory
  # that already existed -- the usual case, since `path` defaults to the
  # repository root -- has its own files taken back out, leaving whatever was
  # there before untouched.
  created_here <- !fs::dir_exists(path)
  new_dirs <- scaffold_dirs()[!fs::dir_exists(fs::path(path, scaffold_dirs()))]
  success <- FALSE
  on.exit(
    if (!success && fs::dir_exists(path)) {
      if (created_here) {
        fs::dir_delete(path)
      } else {
        remove_scaffold(path, files, new_dirs)
      }
    },
    add = TRUE
  )

  fs::dir_create(path)
  cli::cli_h1("Creating publication {.val {title}}")

  data <- list(
    title = title,
    author = author,
    description = description,
    primary_color = primary_color,
    branch = branch,
    repo = repo,
    renv = isTRUE(renv)
  )

  write_project_skeleton(path, name, data)
  write_starter_chapters(path, chapters)

  if (isTRUE(github_actions)) {
    use_publication_workflow(project = path, branch = branch, renv = renv)
  }

  # renv before git, so that renv/ and the lockfile land in the first commit.
  renv_ok <- FALSE
  if (isTRUE(renv)) {
    renv_ok <- init_renv(path)
    if (!renv_ok) {
      # The README and workflow promised a lockfile; regenerate them honestly.
      rewrite_without_renv(path, data, branch, github_actions)
    }
  }

  if (isTRUE(git)) {
    init_git(path, branch = branch)
  }

  success <- TRUE
  # When the project was scaffolded in place the .Rproj sits in the working
  # directory, so pointing at `name/name.Rproj` would name a path that does
  # not exist.
  rproj <- paste0(name, ".Rproj")
  if (path != fs::path_abs(".")) {
    rproj <- as.character(fs::path(name, rproj))
  }
  cli::cli_h2("Next steps")
  cli::cli_ol(c(
    "Open {.path {rproj}}.",
    "Render the site with {.run alberdilabr::render_publication()}.",
    "Push to GitHub and set Settings {cli::symbol$arrow_right} Pages {cli::symbol$arrow_right} Source to {.val GitHub Actions}."
  ))

  if (isTRUE(open)) {
    open_project(path)
  }
  invisible(as.character(path))
}

# Steps -----------------------------------------------------------------------

# Every file the scaffold writes, relative to the project root, so that the
# target directory can be vetted before anything is written. Scaffolding into
# an existing repository is the common case, so "is the directory empty?" is
# the wrong question: what matters is whether we would clobber a file that is
# already there.
publication_files <- function(name, chapters, github_actions) {
  files <- c(
    "index.Rmd", "_bookdown.yml", "README.md", ".gitignore",
    paste0(name, ".Rproj"),
    support_path("setup.R"), support_path("style.css"),
    support_path("references.bib"), support_path("figures", "README.md"),
    fs::path("data", "README.md")
  )
  if (isTRUE(github_actions)) {
    files <- c(files, fs::path(".github", "workflows", "publish.yml"))
  }
  if (length(chapters) > 0) {
    files <- c(files, chapter_path(seq_along(chapters), make_slug(chapters)))
  }
  as.character(files)
}

# Directories the scaffold creates, parents before children so that reversing
# the order removes the deepest first.
scaffold_dirs <- function() {
  c(
    support_dir(), support_path("figures"), "data",
    ".github", ".github/workflows"
  )
}

# Undo an in-place scaffold. The pre-flight check guarantees every path in
# `files` is one we wrote, and `dirs` holds only directories that did not exist
# beforehand, so this cannot take a user's own work with it.
remove_scaffold <- function(path, files, dirs) {
  present <- fs::path(path, files)
  fs::file_delete(present[fs::file_exists(present)])
  for (dir in rev(fs::path(path, dirs))) {
    if (fs::dir_exists(dir) && length(fs::dir_ls(dir, all = TRUE)) == 0) {
      fs::dir_delete(dir)
    }
  }
  invisible(TRUE)
}

check_target_directory <- function(path, files, call = rlang::caller_env()) {
  if (fs::file_exists(path) && !fs::dir_exists(path)) {
    pub_abort(
      c(
        "Cannot create publication at {.path {path}}.",
        x = "A file with that name already exists."
      ),
      class = "alberdilabr_error_exists",
      call = call
    )
  }
  if (!fs::dir_exists(path)) {
    return(invisible(TRUE))
  }

  present <- files[fs::file_exists(fs::path(path, files))]
  if (length(present) > 0) {
    pub_abort(
      c(
        "Cannot create publication in {.path {path}}.",
        x = "{length(present)} file{?s} would be overwritten: {.file {present}}.",
        i = "Move {cli::qty(length(present))}{?it/them} aside, or choose a \
             different {.arg path}."
      ),
      class = "alberdilabr_error_exists",
      call = call
    )
  }
  invisible(TRUE)
}

write_project_skeleton <- function(project, name, data) {
  fs::dir_create(fs::path(project, c(support_dir(), support_path("figures"), "data")))

  # Keep these directories in Git so a fresh clone has them. Their contents
  # differ: data/ is tracked input, alberdilabr/figures/ is knitr output that
  # .gitignore excludes because CI regenerates it.
  write_lines_atomic(
    c(
      "# data/",
      "",
      "Input data for this publication. Tracked in Git.",
      "Delete this file once the directory has real contents."
    ),
    fs::path(project, "data", "README.md")
  )
  write_lines_atomic(
    c(
      "# alberdilabr/figures/",
      "",
      "Figures generated by knitr, via `fig.path` in `index.Rmd`.",
      "",
      "The contents are not tracked in Git: rendering regenerates them, and CI",
      "builds the site from source. Hand-made images that the text refers to",
      "should live outside this directory -- anywhere in the repository that",
      "Git tracks -- so that a render cannot overwrite them."
    ),
    fs::path(project, support_path("figures", "README.md"))
  )

  # The output format lives in index.Rmd rather than a separate _output.yml.
  # bookdown only reads _output.yml from the directory it renders from, so a
  # copy filed away under alberdilabr/ would be ignored in silence and the book
  # would render as gitbook instead.
  use_template("index.Rmd", "index.Rmd", data, project)
  use_template("style.css", support_path("style.css"), data, project)
  use_template("setup.R", support_path("setup.R"), data, project)
  use_template("references.bib", support_path("references.bib"), data, project)
  use_template("README.md", "README.md", data, project)
  use_template("gitignore", ".gitignore", data, project)
  use_template("Rproj", paste0(name, ".Rproj"), data, project)

  write_bookdown_config(project, list(
    book_filename = make_slug(name),
    delete_merged_file = TRUE,
    output_dir = "_site",
    rmd_files = "index.Rmd"
  ))

  cli::cli_alert_success("Wrote project skeleton in {.path {project}}.")
  invisible(project)
}

write_starter_chapters <- function(project, chapters) {
  if (length(chapters) == 0) {
    return(invisible(project))
  }
  available <- chapter_templates()
  for (chapter_title in chapters) {
    slug <- make_slug(chapter_title)
    template <- if (slug %in% available) slug else "chapter"
    add_chapter(
      title = chapter_title,
      template = template,
      project = project,
      quiet = TRUE
    )
  }
  cli::cli_alert_success("Added {length(chapters)} starter chapter{?s}.")
  invisible(project)
}

# When renv was requested but could not run, the README and workflow we already
# wrote describe a lockfile that does not exist. Rewrite them to match reality.
rewrite_without_renv <- function(project, data, branch, github_actions) {
  data$renv <- FALSE
  use_template("index.Rmd", "index.Rmd", data, project, overwrite = TRUE)
  use_template("README.md", "README.md", data, project, overwrite = TRUE)
  if (isTRUE(github_actions)) {
    use_publication_workflow(
      project = project, branch = branch, renv = FALSE, overwrite = TRUE, quiet = TRUE
    )
  }
  invisible(project)
}

# Defaults --------------------------------------------------------------------

default_title <- function(name) {
  words <- strsplit(gsub("[-_.]+", " ", name), " +")[[1]]
  words <- words[nzchar(words)]
  if (length(words) == 0) {
    return(name)
  }
  paste(toupper(substring(words, 1, 1)), substring(words, 2), sep = "", collapse = " ")
}

default_author <- function() {
  option <- getOption("usethis.full_name")
  if (rlang::is_string(option) && nzchar(option)) {
    return(option)
  }
  name <- tryCatch(
    system2("git", c("config", "user.name"), stdout = TRUE, stderr = FALSE),
    error = function(e) character(0),
    warning = function(w) character(0)
  )
  name <- name[nzchar(name)]
  if (length(name) > 0) name[[1]] else "Unknown author"
}

open_project <- function(path) {
  if (!requireNamespace("rstudioapi", quietly = TRUE) ||
      !rstudioapi::isAvailable()) {
    return(invisible(FALSE))
  }
  rproj <- fs::dir_ls(path, glob = "*.Rproj")
  if (length(rproj) == 0) {
    return(invisible(FALSE))
  }
  rstudioapi::openProject(rproj[[1]], newSession = TRUE)
  invisible(TRUE)
}
