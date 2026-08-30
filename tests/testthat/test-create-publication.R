test_that("create_publication() produces a complete project", {
  path <- local_publication()

  expected <- c(
    "index.Rmd", "_bookdown.yml", "README.md", ".gitignore", "testpub.Rproj",
    "alberdilabr/setup.R", "alberdilabr/style.css",
    "alberdilabr/references.bib", "alberdilabr/figures/README.md",
    "data/README.md", ".github/workflows/publish.yml"
  )
  for (f in expected) {
    expect_true(file.exists(file.path(path, f)), label = f)
  }
  for (d in c("alberdilabr", "alberdilabr/figures", "data")) {
    expect_true(dir.exists(file.path(path, d)), label = d)
  }
})

test_that("the project root holds only documents and repository furniture", {
  path <- local_publication(chapters = c("Introduction", "Methods"))

  expect_setequal(
    setdiff(list.files(path, all.files = TRUE, no.. = TRUE), ".github"),
    c("index.Rmd", "01-introduction.Rmd", "02-methods.Rmd",
      "_bookdown.yml", "README.md", ".gitignore", "testpub.Rproj",
      "alberdilabr", "data")
  )
})

test_that("generated configuration is valid and self-consistent", {
  path <- local_publication()
  config <- yaml::read_yaml(file.path(path, "_bookdown.yml"))

  expect_identical(config$output_dir, "_site")
  expect_true(config$delete_merged_file)
  expect_identical(config$rmd_files[[1]], "index.Rmd")

  # Every registered file exists, and every chapter file is registered.
  expect_true(all(file.exists(file.path(path, unlist(config$rmd_files)))))
  expect_setequal(setdiff(unlist(config$rmd_files), "index.Rmd"), chapter_files(path))

  # The output format lives in index.Rmd's front matter, because bookdown
  # ignores an _output.yml that is not in the directory it renders from.
  expect_false(file.exists(file.path(path, "_output.yml")))
  front <- front_matter(path)
  expect_true("bookdown::bs4_book" %in% names(front$output))
  expect_identical(
    front$output[["bookdown::bs4_book"]]$css,
    "alberdilabr/style.css"
  )
  expect_identical(front$bibliography, "alberdilabr/references.bib")
})

test_that("a repo adds edit links with a usable base URL and branch", {
  path <- local_publication(repo = "alberdilab/demo", branch = "main")

  repo <- front_matter(path)$output[["bookdown::bs4_book"]]$repo
  expect_identical(repo$base, "https://github.com/alberdilab/demo")
  expect_identical(repo$branch, "main")
})

test_that("starter chapters are ordered and numbered as requested", {
  path <- local_publication(chapters = c("Introduction", "Methods", "Results"))

  expect_identical(
    unlist(rmd_files(path)),
    c("index.Rmd", "01-introduction.Rmd",
      "02-methods.Rmd", "03-results.Rmd")
  )
})

test_that("chapters use their matching template when one exists", {
  path <- local_publication(chapters = c("Results", "Sensitivity Analysis"))

  results <- readLines(file.path(path, "01-results.Rmd"))
  expect_true(any(grepl("fig.cap", results, fixed = TRUE)))

  # No shipped template matches this title, so it falls back to "chapter".
  generic <- readLines(file.path(path, "02-sensitivity-analysis.Rmd"))
  expect_identical(generic[1], "# Sensitivity Analysis {#sensitivity-analysis}")
})

test_that("a project can be created with no starter chapters", {
  path <- local_publication(chapters = character(0))

  expect_identical(unlist(rmd_files(path)), "index.Rmd")
  expect_length(chapter_files(path), 0)
})

test_that("an existing directory is scaffolded in place", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "repo")
  dir.create(path)
  writeLines("keep me", file.path(path, "important.txt"))
  dir.create(file.path(path, "src"))

  suppressMessages(create_publication(
    path, renv = FALSE, git = FALSE, open = FALSE
  ))

  expect_true(file.exists(file.path(path, "_bookdown.yml")))
  expect_true(file.exists(file.path(path, "repo.Rproj")))
  # Whatever the directory already held is left alone.
  expect_identical(readLines(file.path(path, "important.txt")), "keep me")
  expect_true(dir.exists(file.path(path, "src")))
})

test_that("path defaults to the working directory", {
  dir <- withr::local_tempdir(pattern = "inplace")
  withr::local_dir(dir)

  suppressMessages(create_publication(
    renv = FALSE, git = FALSE, open = FALSE, chapters = "Introduction"
  ))

  expect_true(file.exists("_bookdown.yml"))
  expect_true(file.exists(paste0(basename(dir), ".Rproj")))
  expect_true(file.exists("01-introduction.Rmd"))
})

test_that("a file the scaffold would overwrite stops it before anything is written", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "occupied")
  dir.create(path)
  writeLines("mine", file.path(path, "index.Rmd"))
  writeLines("keep me", file.path(path, "important.txt"))

  expect_error(
    create_publication(path, renv = FALSE, git = FALSE, open = FALSE),
    class = "alberdilabr_error_exists"
  )
  # The pre-existing contents must be untouched, and nothing new written.
  expect_identical(readLines(file.path(path, "index.Rmd")), "mine")
  expect_identical(readLines(file.path(path, "important.txt")), "keep me")
  expect_false(file.exists(file.path(path, "_bookdown.yml")))
})

test_that("creating over an existing file fails", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "afile")
  writeLines("x", path)

  expect_error(
    create_publication(path, renv = FALSE, git = FALSE, open = FALSE),
    class = "alberdilabr_error_exists"
  )
})

test_that("a failed creation leaves no partial project behind", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "doomed")

  # Force a failure after the directory has been created.
  local_mocked_bindings(write_starter_chapters = function(...) stop("boom"))
  expect_error(
    suppressMessages(create_publication(path, renv = FALSE, git = FALSE, open = FALSE)),
    "boom"
  )
  expect_false(dir.exists(path))
})

test_that("a failed in-place creation removes only what it wrote", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "repo")
  dir.create(path)
  writeLines("keep me", file.path(path, "important.txt"))
  dir.create(file.path(path, "alberdilabr"))
  writeLines("mine", file.path(path, "alberdilabr", "notes.md"))

  local_mocked_bindings(write_starter_chapters = function(...) stop("boom"))
  expect_error(
    suppressMessages(create_publication(path, renv = FALSE, git = FALSE, open = FALSE)),
    "boom"
  )

  expect_true(dir.exists(path))
  expect_identical(readLines(file.path(path, "important.txt")), "keep me")
  # A directory that was already there survives, along with its contents.
  expect_identical(readLines(file.path(path, "alberdilabr", "notes.md")), "mine")
  # Everything the scaffold wrote is gone, directories included.
  expect_false(file.exists(file.path(path, "index.Rmd")))
  expect_false(file.exists(file.path(path, "alberdilabr", "setup.R")))
  expect_false(file.exists(file.path(path, "_bookdown.yml")))
  # ...but a directory that was already there is kept, not swept away with it.
  expect_true(dir.exists(file.path(path, "alberdilabr")))
})

test_that("the workflow matches the project's renv state", {
  path <- local_publication()
  workflow <- readLines(file.path(path, ".github", "workflows", "publish.yml"))

  # renv = FALSE, so no step may restore a lockfile. Match the `uses:` line
  # rather than the word, which also appears in the explanatory comment.
  steps <- grep("^\\s*-?\\s*uses:", workflow, value = TRUE)
  expect_false(any(grepl("setup-renv", steps)))
  expect_true(any(grepl("setup-r@v2", steps)))
  expect_true(any(grepl("install.packages", workflow, fixed = TRUE)))
  expect_true(any(grepl('path: "_site"', workflow, fixed = TRUE)))
  # GitHub expression syntax must survive templating.
  expect_true(any(grepl("${{ secrets.GITHUB_TOKEN }}", workflow, fixed = TRUE)))
  expect_true(any(grepl("hashFiles('**/*.Rmd')", workflow, fixed = TRUE)))
})

test_that("titles and authors default sensibly", {
  expect_identical(default_title("my-analysis"), "My Analysis")
  expect_identical(default_title("gut_microbiome.study"), "Gut Microbiome Study")
})

test_that("publication_root() finds the project from a subdirectory", {
  path <- local_publication()
  expect_identical(
    fs::path_real(publication_root(file.path(path, "alberdilabr"))),
    fs::path_real(path)
  )
  expect_error(
    publication_root(withr::local_tempdir()),
    class = "alberdilabr_error_no_project"
  )
})

test_that("generated figures are not tracked but the directory is", {
  path <- local_publication(chapters = character(0))
  gitignore <- readLines(file.path(path, ".gitignore"))

  expect_true(any(grepl("^alberdilabr/figures/\\*$", gitignore)))
  expect_true(any(grepl("^!alberdilabr/figures/README.md$", gitignore)))
  expect_true(file.exists(file.path(path, "alberdilabr", "figures", "README.md")))
  # data/ is tracked input, so it must not be ignored.
  expect_false(any(grepl("^data/", gitignore)))
})
