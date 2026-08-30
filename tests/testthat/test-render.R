# Integration tests. These invoke pandoc and knitr and take tens of seconds, so
# they are kept apart from the unit tests above and skipped where the toolchain
# is unavailable.

skip_render_tests <- function() {
  skip_on_cran()
  skip_if_not_installed("bookdown")
  skip_if_not_installed("bslib")
  skip_if_not_installed("downlit")
  skip_if_not(rmarkdown::pandoc_available("2.0"), "pandoc is not available")
}

test_that("a generated project renders to a complete site", {
  skip_render_tests()
  path <- local_publication(chapters = c("Introduction", "Results"))

  site <- suppressMessages(render_publication(path, quiet = TRUE))

  expect_true(file.exists(file.path(site, "index.html")))
  expect_true(file.exists(file.path(site, "introduction.html")))
  expect_true(file.exists(file.path(site, "results.html")))

  # The results template plots a figure; it must have been executed.
  expect_true(any(grepl(
    "results-example-figure",
    readLines(file.path(site, "results.html"), warn = FALSE)
  )))
})

test_that("the generated project renders without the alberdilabr package", {
  skip_render_tests()
  path <- local_publication(chapters = "Introduction")

  # The core architectural promise: bookdown alone can build the project.
  withr::with_dir(path, {
    expect_no_error(bookdown::render_book("index.Rmd", quiet = TRUE))
  })
  expect_true(file.exists(file.path(path, "_site", "index.html")))
})

test_that("render_publication() refuses to run with missing chapter files", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  file.remove(file.path(path, "chapters", "02-methods.Rmd"))

  expect_error(
    render_publication(path),
    class = "alberdilabr_error_missing_files"
  )
})

test_that("check_publication(render = TRUE) reports a successful build", {
  skip_render_tests()
  path <- local_publication(chapters = "Introduction")

  res <- suppressMessages(check_publication(path, render = TRUE, quiet = TRUE))
  rendering <- res[res$category == "rendering", ]

  expect_identical(nrow(rendering), 1L)
  expect_identical(rendering$status, "pass")
})

test_that("check_publication(render = TRUE) reports a broken build", {
  skip_render_tests()
  path <- local_publication(chapters = "Introduction")
  writeLines(
    c("# Introduction {#introduction}", "",
      "```{r}", "stop('deliberate failure')", "```"),
    file.path(path, "chapters", "01-introduction.Rmd")
  )

  res <- suppressMessages(check_publication(path, render = TRUE, quiet = TRUE))
  rendering <- res[res$category == "rendering", ]

  expect_identical(rendering$status, "fail")
  expect_match(rendering$message, "render failed")
})
