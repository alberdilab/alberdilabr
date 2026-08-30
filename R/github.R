# Git and GitHub helpers.
#
# Git is driven through the command-line client rather than a package binding.
# Anyone deploying to GitHub Pages already has git installed, so this costs no
# dependency, and the commands are ones the user can read and repeat by hand.

#' Add a GitHub Pages publishing workflow
#'
#' Writes `.github/workflows/publish.yml`, a workflow that renders the book and
#' deploys the output directory to GitHub Pages using the artifact-based
#' deployment actions. Generated HTML is never committed.
#'
#' @param project Path to the publication project.
#' @param branch Branch whose pushes trigger a deployment.
#' @param renv Whether to restore dependencies from `renv.lock`. `NULL` (the
#'   default) detects whether the project has a lockfile.
#' @param overwrite Whether to replace an existing workflow file.
#' @param quiet Whether to suppress the success message.
#'
#' @return The path to the workflow file, invisibly.
#' @export
#' @examples
#' \dontrun{
#' use_github_publication(branch = "main")
#' }
use_github_publication <- function(project = ".",
                                   branch = "main",
                                   renv = NULL,
                                   overwrite = FALSE,
                                   quiet = FALSE) {
  project <- publication_root(project)
  config <- read_bookdown_config(project)
  renv <- renv %||% fs::file_exists(fs::path(project, "renv.lock"))

  path <- use_publication_workflow(
    project = project,
    branch = branch,
    renv = renv,
    output_dir = config$output_dir %||% "_book",
    overwrite = overwrite,
    quiet = quiet
  )

  if (!quiet) {
    cli::cli_alert_info(
      "Enable Pages at Settings {cli::symbol$arrow_right} Pages {cli::symbol$arrow_right} Source {cli::symbol$arrow_right} {.val GitHub Actions}."
    )
  }
  invisible(path)
}

# Internal worker, also called during project creation before _bookdown.yml is
# guaranteed to be readable by publication_root().
use_publication_workflow <- function(project,
                                     branch = "main",
                                     renv = TRUE,
                                     output_dir = "_site",
                                     overwrite = FALSE,
                                     quiet = FALSE) {
  template <- if (isTRUE(renv)) "publish-renv.yml" else "publish-simple.yml"
  save_as <- fs::path(".github", "workflows", "publish.yml")

  path <- use_template(
    fs::path("workflows", template),
    save_as = save_as,
    data = list(branch = branch, output_dir = output_dir),
    project = project,
    overwrite = overwrite
  )
  if (!quiet) {
    cli::cli_alert_success("Wrote {.file {save_as}}.")
  }
  invisible(path)
}

# Git -------------------------------------------------------------------------

git_available <- function() {
  nzchar(Sys.which("git"))
}

git_run <- function(args, project) {
  suppressWarnings(system2(
    "git",
    c("-C", shQuote(project), args),
    stdout = TRUE,
    stderr = TRUE
  ))
}

init_git <- function(project, branch = "main") {
  if (!git_available()) {
    cli::cli_alert_warning(
      "{.command git} was not found on the PATH; skipping repository setup."
    )
    return(invisible(FALSE))
  }
  if (fs::dir_exists(fs::path(project, ".git"))) {
    cli::cli_alert_info("{.path .git} already exists; leaving it alone.")
    return(invisible(FALSE))
  }

  out <- git_run(c("init", "--initial-branch", branch), project)
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) {
    # --initial-branch needs git >= 2.28; fall back and rename afterwards.
    git_run("init", project)
    git_run(c("checkout", "-b", branch), project)
  }
  git_run(c("add", "-A"), project)
  commit <- git_run(
    c("commit", "--no-verify", "-m", shQuote("Create publication project")),
    project
  )
  if (!is.null(attr(commit, "status")) && attr(commit, "status") != 0) {
    cli::cli_alert_warning(c(
      "Initialised Git but could not create the first commit.",
      "i" = "Set {.command git config user.name} and {.command user.email}, then commit manually."
    ))
    return(invisible(FALSE))
  }
  cli::cli_alert_success("Initialised Git on branch {.val {branch}} with an initial commit.")
  invisible(TRUE)
}

# renv ------------------------------------------------------------------------

# renv::init() is run in a separate R process on purpose. Called in-process it
# would rewrite the calling session's library paths and load a different set of
# packages underneath the user, which is a surprising side effect for a
# scaffolding function.
init_renv <- function(project) {
  if (!requireNamespace("renv", quietly = TRUE)) {
    cli::cli_alert_warning(c(
      "The {.pkg renv} package is not installed; skipping lockfile setup.",
      "i" = 'Install it and run {.run renv::init()} in the project to pin dependencies.'
    ))
    return(invisible(FALSE))
  }

  cli::cli_alert_info(
    "Initialising {.pkg renv}. This installs the project's dependencies and can take several minutes{cli::symbol$ellipsis}"
  )

  rscript <- file.path(R.home("bin"), "Rscript")
  code <- sprintf(
    'renv::init(project = "%s", restart = FALSE)',
    gsub("\\\\", "/", as.character(project))
  )
  status <- suppressWarnings(system2(
    rscript,
    c("-e", shQuote(code)),
    stdout = FALSE,
    stderr = FALSE
  ))

  if (!identical(status, 0L) || !fs::file_exists(fs::path(project, "renv.lock"))) {
    cli::cli_alert_warning(c(
      "{.fn renv::init} did not produce a lockfile.",
      "i" = "Run {.run renv::init()} inside the project to see the error."
    ))
    return(invisible(FALSE))
  }
  cli::cli_alert_success("Initialised {.pkg renv} and wrote {.file renv.lock}.")
  invisible(TRUE)
}
