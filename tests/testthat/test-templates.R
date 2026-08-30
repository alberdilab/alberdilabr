test_that("shipped chapter templates are all usable", {
  path <- local_publication(chapters = character(0))

  for (template in chapter_templates()) {
    title <- paste("Test", template)
    expect_no_error(
      suppressMessages(add_chapter(title, template = template, project = path))
    )
  }
  expect_length(chapter_files(path), length(chapter_templates()))
})

test_that("templates that would trip whisker's brace quirk are rejected", {
  # whisker silently drops a placeholder immediately followed by "}", which is
  # exactly how someone would naively write a heading anchor.
  dir <- withr::local_tempdir()
  bad <- file.path(dir, "bad.Rmd")
  writeLines("# {{{title}}} {#{{{slug}}}}", bad)

  expect_error(
    whisker_hazard(readLines(bad), bad),
    class = "alberdilabr_error_bad_template"
  )
})

test_that("no shipped template trips the whisker brace quirk", {
  dir <- system.file("templates", package = "alberdilabr")
  files <- list.files(dir, recursive = TRUE, full.names = TRUE)

  for (f in files) {
    expect_no_error(whisker_hazard(readLines(f, warn = FALSE), f))
  }
})

test_that("titles containing markup survive templating unescaped", {
  path <- local_publication(chapters = character(0))

  suppressMessages(add_chapter("Costs & Benefits", project = path))

  expect_identical(
    readLines(file.path(path, "01-costs-benefits.Rmd"))[1],
    "# Costs & Benefits {#costs-benefits}"
  )
})

test_that("configuration round-trips unknown keys", {
  path <- local_publication(chapters = "Introduction")
  config <- read_bookdown_config(path)
  config$before_chapter_script <- "alberdilabr/setup.R"
  write_bookdown_config(path, config)

  reread <- yaml::read_yaml(file.path(path, "_bookdown.yml"))
  expect_identical(reread$before_chapter_script, "alberdilabr/setup.R")

  # And a chapter operation must not drop it.
  suppressMessages(add_chapter("Methods", project = path))
  reread <- yaml::read_yaml(file.path(path, "_bookdown.yml"))
  expect_identical(reread$before_chapter_script, "alberdilabr/setup.R")
  expect_length(reread$rmd_files, 3)
})
