# The renv code paths that do not require running renv::init(), which installs
# packages and takes minutes. Lockfiles here are fixtures, not real ones.

write_lockfile <- function(project, packages) {
  entries <- vapply(packages, function(p) sprintf(
    '    "%s": {\n      "Package": "%s",\n      "Version": "1.0.0",\n      "Source": "Repository"\n    }',
    p, p
  ), character(1))
  writeLines(
    c('{', '  "R": {', '    "Version": "4.3.3"', '  },', '  "Packages": {',
      paste(entries, collapse = ",\n"), '  }', '}'),
    file.path(project, "renv.lock")
  )
}

test_that("use_github_publication() writes the renv workflow when a lockfile exists", {
  path <- local_publication(chapters = character(0), github_actions = FALSE)
  write_lockfile(path, render_dependencies)

  suppressMessages(use_github_publication(path))
  steps <- grep(
    "^\\s*-?\\s*uses:", readLines(file.path(path, ".github/workflows/publish.yml")),
    value = TRUE
  )

  expect_true(any(grepl("r-lib/actions/setup-renv@v2", steps, fixed = TRUE)))
})

test_that("use_github_publication() writes the unpinned workflow without a lockfile", {
  path <- local_publication(chapters = character(0), github_actions = FALSE)

  suppressMessages(use_github_publication(path))
  workflow <- readLines(file.path(path, ".github/workflows/publish.yml"))
  steps <- grep("^\\s*-?\\s*uses:", workflow, value = TRUE)

  expect_false(any(grepl("setup-renv", steps)))
  expect_true(any(grepl("install.packages", workflow, fixed = TRUE)))
})

test_that("the workflow's artifact path follows output_dir", {
  path <- local_publication(chapters = character(0), github_actions = FALSE)
  config <- read_bookdown_config(path)
  config$output_dir <- "docs"
  write_bookdown_config(path, config)

  suppressMessages(use_github_publication(path))

  expect_identical(
    workflow_artifact_path(file.path(path, ".github/workflows/publish.yml")),
    "docs"
  )
  # And the consistency check must therefore pass.
  expect_identical(check_status(path, "workflow uploads"), "pass")
})

test_that("a complete lockfile satisfies the reproducibility checks", {
  path <- local_publication(chapters = character(0))
  write_lockfile(path, render_dependencies)

  expect_identical(check_status(path, "renv.lock is present"), "pass")
  expect_identical(check_status(path, "records every package"), "pass")
})

test_that("a lockfile missing render dependencies is reported", {
  path <- local_publication(chapters = character(0))
  write_lockfile(path, c("bookdown", "knitr"))

  expect_identical(check_status(path, "does not record"), "warn")
})

test_that("an unparseable lockfile is reported as a failure", {
  path <- local_publication(chapters = character(0))
  writeLines("{ not json", file.path(path, "renv.lock"))

  expect_identical(check_status(path, "could not be parsed"), "fail")
})

test_that("an renv project whose .Rprofile does not activate it is reported", {
  path <- local_publication(chapters = character(0))
  write_lockfile(path, render_dependencies)
  dir.create(file.path(path, "renv"))
  writeLines("options(stringsAsFactors = FALSE)", file.path(path, ".Rprofile"))

  expect_identical(check_status(path, "does not source renv/activate.R"), "warn")
})
