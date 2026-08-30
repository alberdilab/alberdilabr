test_that("add_chapter() creates, names and registers a chapter", {
  path <- local_publication(chapters = "Introduction")

  result <- suppressMessages(add_chapter("Sensitivity Analysis", project = path))

  expect_identical(result, "02-sensitivity-analysis.Rmd")
  expect_true(file.exists(file.path(path, result)))
  expect_identical(
    unlist(rmd_files(path)),
    c("index.Rmd", "01-introduction.Rmd",
      "02-sensitivity-analysis.Rmd")
  )

  body <- readLines(file.path(path, result))
  expect_identical(body[1], "# Sensitivity Analysis {#sensitivity-analysis}")
})

test_that("add_chapter() accepts an explicit slug", {
  path <- local_publication(chapters = character(0))

  suppressMessages(add_chapter("A Very Long Title", slug = "short", project = path))

  expect_true(file.exists(file.path(path, "01-short.Rmd")))
  expect_identical(
    readLines(file.path(path, "01-short.Rmd"))[1],
    "# A Very Long Title {#short}"
  )
})

test_that("add_chapter() inserts at a requested position and renumbers", {
  path <- local_publication(chapters = c("Introduction", "Methods", "Results"))

  suppressMessages(
    add_chapter("Study Design", after = "introduction", project = path)
  )

  expect_identical(
    unlist(rmd_files(path)),
    c("index.Rmd", "01-introduction.Rmd", "02-study-design.Rmd",
      "03-methods.Rmd", "04-results.Rmd")
  )
  # Configuration and disk agree after renumbering.
  expect_setequal(
    chapter_files(path),
    c("01-introduction.Rmd", "02-study-design.Rmd",
      "03-methods.Rmd", "04-results.Rmd")
  )
})

test_that("add_chapter(after = 0) inserts first", {
  path <- local_publication(chapters = c("Methods", "Results"))

  suppressMessages(add_chapter("Introduction", after = 0, project = path))

  expect_identical(unlist(rmd_files(path))[2], "01-introduction.Rmd")
})

test_that("duplicate chapters are rejected without touching the project", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  before_config <- rmd_files(path)
  before_files <- chapter_files(path)

  expect_error(
    add_chapter("Introduction", project = path),
    class = "alberdilabr_error_duplicate_chapter"
  )
  expect_identical(rmd_files(path), before_config)
  expect_identical(chapter_files(path), before_files)
})

test_that("an unknown template fails before any file is created", {
  path <- local_publication(chapters = character(0))

  expect_error(
    add_chapter("Nope", template = "does-not-exist", project = path),
    class = "alberdilabr_error_unknown_template"
  )
  expect_length(chapter_files(path), 0)
  expect_identical(unlist(rmd_files(path)), "index.Rmd")
})

test_that("invalid arguments produce actionable errors", {
  path <- local_publication(chapters = "Introduction")

  expect_error(add_chapter("", project = path), class = "alberdilabr_error_type")
  expect_error(
    add_chapter("Ok", slug = "Not A Slug", project = path),
    class = "alberdilabr_error_slug"
  )
  expect_error(
    add_chapter("Ok", after = "nonexistent", project = path),
    class = "alberdilabr_error_no_chapter"
  )
  expect_error(
    add_chapter("Ok", after = 99, project = path),
    class = "alberdilabr_error_position"
  )
})

test_that("remove_chapter() deletes the file and renumbers the rest", {
  path <- local_publication(chapters = c("Introduction", "Methods", "Results"))

  suppressMessages(remove_chapter("methods", project = path))

  expect_identical(
    unlist(rmd_files(path)),
    c("index.Rmd", "01-introduction.Rmd", "02-results.Rmd")
  )
  expect_identical(chapter_files(path), c("01-introduction.Rmd", "02-results.Rmd"))
})

test_that("remove_chapter(delete_file = FALSE) keeps the file but unregisters it", {
  path <- local_publication(chapters = c("Introduction", "Methods"))

  suppressMessages(remove_chapter("methods", delete_file = FALSE, project = path))

  expect_false("02-methods.Rmd" %in% unlist(rmd_files(path)))
  expect_true(file.exists(file.path(path, "02-methods.Rmd")))
})

test_that("removing an unknown chapter errors and changes nothing", {
  path <- local_publication(chapters = "Introduction")
  before <- rmd_files(path)

  expect_error(
    remove_chapter("ghost", project = path),
    class = "alberdilabr_error_no_chapter"
  )
  expect_identical(rmd_files(path), before)
  expect_identical(chapter_files(path), "01-introduction.Rmd")
})

test_that("move_chapter() reorders and keeps files in sync", {
  path <- local_publication(
    chapters = c("Introduction", "Methods", "Results", "Discussion")
  )

  suppressMessages(move_chapter("discussion", after = "introduction", project = path))

  expect_identical(
    unlist(rmd_files(path)),
    c("index.Rmd", "01-introduction.Rmd", "02-discussion.Rmd",
      "03-methods.Rmd", "04-results.Rmd")
  )
  expect_setequal(
    chapter_files(path),
    c("01-introduction.Rmd", "02-discussion.Rmd",
      "03-methods.Rmd", "04-results.Rmd")
  )
})

test_that("move_chapter() can move a chapter to the front", {
  path <- local_publication(chapters = c("Introduction", "Methods", "Results"))

  suppressMessages(move_chapter("results", after = 0, project = path))

  expect_identical(unlist(rmd_files(path))[2], "01-results.Rmd")
  # Swapping neighbours must not lose a file to a mid-rename collision.
  expect_length(chapter_files(path), 3)
})

test_that("a swap of adjacent chapters preserves both files", {
  path <- local_publication(chapters = c("Introduction", "Methods"))
  intro <- readLines(file.path(path, "01-introduction.Rmd"))

  suppressMessages(move_chapter("methods", after = 0, project = path))

  expect_identical(chapter_files(path), c("01-methods.Rmd", "02-introduction.Rmd"))
  expect_identical(readLines(file.path(path, "02-introduction.Rmd")), intro)
})

test_that("chapters can be referenced by slug, filename or path", {
  path <- local_publication(chapters = c("Introduction", "Methods"))

  expect_no_error(suppressMessages(move_chapter("methods", after = 0, project = path)))
  expect_no_error(
    suppressMessages(move_chapter("01-methods.Rmd", after = 1, project = path))
  )
  expect_no_error(
    suppressMessages(
      move_chapter("02-methods.Rmd", after = 0, project = path)
    )
  )
})

test_that("make_slug() handles punctuation, case and accents", {
  expect_identical(make_slug("Sensitivity Analysis"), "sensitivity-analysis")
  expect_identical(make_slug("Results & Discussion"), "results-discussion")
  expect_identical(make_slug("  Leading/trailing  "), "leading-trailing")
  expect_identical(make_slug("Analisis"), "analisis")
})
