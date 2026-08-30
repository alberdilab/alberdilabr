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
#' @param path Directory to create the project in. Must not already exist, or
#'   must be an empty directory.
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
create_publication <- function(path,
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
  check_target_directory(path)

  name <- fs::path_file(path)
  title <- title %||% default_title(name)
  author <- author %||% default_author()
  chapters <- as.character(chapters)

  if (!rlang::is_string(branch) || !nzchar(branch)) {
    pub_abort(
      "{.arg branch} must be a single non-empty string.",
      class = "alberdilabr_error_type"
    )
  }

  # Everything below either completes or leaves no trace: if we created the
  # directory and any step fails, the partial project is removed rather than
  # left for the user to clean up by hand.
  created_here <- !fs::dir_exists(path)
  success <- FALSE
  on.exit(
    if (!success && created_here && fs::dir_exists(path)) fs::dir_delete(path),
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
  cli::cli_h2("Next steps")
  cli::cli_ol(c(
    "Open {.path {fs::path(name, paste0(name, '.Rproj'))}}.",
    "Render the site with {.run alberdilabr::render_publication()}.",
    "Push to GitHub and set Settings {cli::symbol$arrow_right} Pages {cli::symbol$arrow_right} Source to {.val GitHub Actions}."
  ))

  if (isTRUE(open)) {
    open_project(path)
  }
  invisible(as.character(path))
}

# Steps -----------------------------------------------------------------------

check_target_directory <- function(path, call = rlang::caller_env()) {
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
  if (fs::dir_exists(path)) {
    contents <- fs::dir_ls(path, all = TRUE)
    contents <- contents[!fs::path_file(contents) %in% c(".", "..")]
    if (length(contents) > 0) {
      pub_abort(
        c(
          "Cannot create publication at {.path {path}}.",
          x = "The directory already exists and is not empty.",
          i = "Choose a different {.arg path}, or empty the directory first."
        ),
        class = "alberdilabr_error_exists",
        call = call
      )
    }
  }
  invisible(TRUE)
}

write_project_skeleton <- function(project, name, data) {
  fs::dir_create(fs::path(project, c("chapters", "R", "data", "figures", "assets")))

  # Keep these directories in Git so a fresh clone has them. Their contents
  # differ: data/ is tracked input, figures/ is knitr output that .gitignore
  # excludes because CI regenerates it.
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
      "# figures/",
      "",
      "Figures generated by knitr, via `fig.path` in `index.Rmd`.",
      "",
      "The contents are not tracked in Git: rendering regenerates them, and CI",
      "builds the site from source. Hand-made images that the text refers to",
      "belong in `assets/` instead, where they are tracked."
    ),
    fs::path(project, "figures", "README.md")
  )

  use_template("index.Rmd", "index.Rmd", data, project)
  use_template(
    if (is.null(data$repo)) "_output_norepo.yml" else "_output.yml",
    "_output.yml", data, project
  )
  use_template("style.css", fs::path("assets", "style.css"), data, project)
  use_template("setup.R", fs::path("R", "setup.R"), data, project)
  use_template("references.bib", "references.bib", data, project)
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
