test_that("a freshly created project passes every check", {
  path <- local_publication()
  res <- suppressMessages(check_publication(path, quiet = TRUE))

  expect_s3_class(res, "publication_check")
  expect_identical(sum(res$status == "fail"), 0L)

  # renv = FALSE, so the only expected warning is the missing lockfile.
  warnings <- res$message[res$status == "warn"]
  expect_length(warnings, 1)
  expect_match(warnings, "renv.lock is missing")
})

test_that("a missing registered chapter file is reported as a failure", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  file.remove(file.path(path, "chapters", "02-methods.Rmd"))

  expect_identical(check_status(path, "registered file.*missing"), "fail")
})

test_that("an unregistered chapter file is reported", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Orphan {#orphan}", "", "Never registered."),
    file.path(path, "chapters", "99-orphan.Rmd")
  )

  expect_identical(check_status(path, "not registered in _bookdown.yml"), "warn")
})

test_that("duplicate chapter identifiers are reported as a failure", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  writeLines(
    c("# Methods {#introduction}", "", "Clashing id."),
    file.path(path, "chapters", "02-methods.Rmd")
  )

  expect_identical(check_status(path, "duplicate chapter identifier"), "fail")
})

test_that("a chapter with two top-level headings is reported as a failure", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# One {#one}", "", "text", "", "# Two {#two}", "", "more"),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  expect_identical(check_status(path, "top-level headings"), "fail")
})

test_that("a chapter heading without an identifier is reported", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Introduction", "", "No anchor."),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  expect_identical(check_status(path, "without"), "warn")
})

test_that("a heading id that disagrees with the filename is reported", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Introduction {#something-else}", "", "Drifted."),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  expect_identical(check_status(path, "does not match filename slug"), "warn")
})

test_that("duplicate knitr chunk labels are reported as a failure", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  for (f in c("01-introduction.Rmd", "02-methods.Rmd")) {
    slug <- sub("^[0-9]+-|[.]Rmd$", "", f)
    writeLines(
      c(paste0("# X {#", slug, "}"), "", "```{r shared-label}", "1 + 1", "```"),
      file.path(path, "chapters", f)
    )
  }

  expect_identical(check_status(path, "duplicate chunk label"), "fail")
})

test_that("a captioned figure without a chunk label is reported", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Introduction {#introduction}", "",
      '```{r fig.cap = "Uncrossreferenceable."}', "plot(1)", "```"),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  expect_identical(check_status(path, "unlabelled figure"), "warn")
})

test_that("headings inside code fences are not mistaken for chapter headings", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Introduction {#introduction}", "",
      "```{r commented}",
      "# This is an R comment, not a heading",
      "## Neither is this",
      "```",
      "",
      "```",
      "# Nor this, in a plain fence",
      "```"),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  res <- suppressMessages(check_publication(path, quiet = TRUE))
  expect_identical(sum(res$status == "fail"), 0L)
})

test_that("YAML front matter is not scanned for headings", {
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("---", "title: Something", "---", "",
      "# Introduction {#introduction}", "", "text"),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  res <- suppressMessages(check_publication(path, quiet = TRUE))
  expect_identical(sum(res$status == "fail"), 0L)
})

test_that("a mismatch between output_dir and the workflow is reported", {
  path <- local_publication()
  workflow <- file.path(path, ".github", "workflows", "publish.yml")
  writeLines(
    sub('path: "_site"', 'path: "_book"', readLines(workflow), fixed = TRUE),
    workflow
  )

  expect_identical(check_status(path, "workflow uploads"), "fail")
})

test_that("a missing publishing workflow is reported", {
  path <- local_publication(github_actions = FALSE)

  expect_identical(check_status(path, "publish.yml is missing"), "warn")
})

test_that("an untracked output directory is required in .gitignore", {
  path <- local_publication()
  gitignore <- file.path(path, ".gitignore")
  writeLines(grep("^_site/$", readLines(gitignore), invert = TRUE, value = TRUE), gitignore)

  expect_identical(check_status(path, "not listed in .gitignore"), "warn")
})

test_that("malformed _bookdown.yml produces an actionable error", {
  path <- local_publication()
  writeLines("rmd_files: [unclosed", file.path(path, "_bookdown.yml"))

  expect_error(
    check_publication(path, quiet = TRUE),
    class = "alberdilabr_error_bad_config"
  )
})

test_that("a missing CSS file referenced by _output.yml is reported", {
  path <- local_publication()
  file.remove(file.path(path, "assets", "style.css"))

  expect_identical(check_status(path, "which does not exist"), "fail")
})
