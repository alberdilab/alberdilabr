# alberdilabr 0.1.0

First release.

## Project scaffolding

* `create_publication()` scaffolds a complete bookdown publication: chapter
  files, `_bookdown.yml`, `_output.yml`, a shared `R/setup.R`, an RStudio
  project file, and the GitHub Pages workflow. The result is an ordinary
  bookdown project that renders with `bookdown::render_book()` whether or not
  this package is installed.
* `use_github_publication()` adds or refreshes the Pages deployment workflow on
  an existing project, choosing the `renv`-pinned or unpinned variant from
  whether `renv.lock` is present.

## Chapter management

* `add_chapter()`, `remove_chapter()` and `move_chapter()` keep the files in
  `chapters/` and the `rmd_files` list in `_bookdown.yml` consistent, including
  renumbering on reorder.
* `chapter_templates()` lists the available chapter templates; `make_slug()` and
  `publication_root()` are exported for scripting.

## Rendering

* `render_publication()` builds into the `output_dir` recorded in
  `_bookdown.yml`; `preview_publication()` serves a live-reloading local
  preview. Neither hardcodes the output directory.

## Validation

* `check_publication()` reports on structure, document conventions (single
  top-level heading, unique heading identifiers and chunk labels,
  cross-referenceable figures), reproducibility, and whether the workflow's
  upload path agrees with bookdown's output directory. It runs offline and
  returns a data frame, so individual checks can be used programmatically.
* `check_publication(render = TRUE)` adds a full build as an integration test.
