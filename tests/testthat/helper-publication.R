# A minimal project, created as fast as possible: no renv (which installs
# packages), no Git (which shells out), no starter chapters unless asked.
local_publication <- function(chapters = c("Introduction", "Methods"),
                              ...,
                              env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "testpub")
  suppressMessages(create_publication(
    path,
    title = "Test Publication",
    author = "Test Author",
    chapters = chapters,
    renv = FALSE,
    git = FALSE,
    open = FALSE,
    ...
  ))
  path
}

rmd_files <- function(project) {
  yaml::read_yaml(file.path(project, "_bookdown.yml"))$rmd_files
}

chapter_files <- function(project) {
  sort(list.files(file.path(project, "chapters"), pattern = "[.]Rmd$"))
}

# Status of a single named check, for asserting that a broken fixture is caught.
check_status <- function(project, pattern) {
  res <- suppressMessages(check_publication(project, quiet = TRUE))
  hit <- grep(pattern, res$message)
  if (length(hit) == 0) return(NA_character_)
  res$status[hit[1]]
}
