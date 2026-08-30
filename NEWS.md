# alberdilabr 0.3.0

## Project layout

The scaffold now puts the documents you write in the project root and files
everything else under `alberdilabr/`. A new project's root holds `index.Rmd`,
the numbered chapter files, `_bookdown.yml`, `README.md`, `.gitignore`, the
`.Rproj` and `data/` -- nothing else.

* Chapters are created as `NN-slug.Rmd` in the project root rather than in
  `chapters/`. `add_chapter()`, `move_chapter()` and `remove_chapter()`
  renumber them there.
* `R/setup.R`, `assets/style.css`, `references.bib` and the generated
  `figures/` directory move to `alberdilabr/`. The `R/` and `assets/`
  directories are no longer created.
* `_output.yml` is gone. Its contents now live in the `output` field of
  `index.Rmd`, because bookdown reads `_output.yml` only from the directory it
  renders from: a copy filed under `alberdilabr/` would have been ignored in
  silence, and the book would have rendered as `gitbook` instead of `bs4_book`.
* `_bookdown.yml` stays in the project root, for the same reason. Keeping it
  there is what preserves the package's central promise -- that
  `bookdown::render_book()` builds the project on its own, with no arguments
  and without this package, from RStudio's *Build Book* button as readily as
  from the GitHub Actions workflow.

Existing projects are unaffected and keep rendering: this changes what
`create_publication()` writes, not what the other functions can read. To adopt
the new layout in a project scaffolded by 0.1.x, move the files by hand and
update the paths in `_bookdown.yml` and `index.Rmd`.

## Bug fixes

* `create_publication(repo = "owner/name")` produced edit and source links to
  `owner/name/edit/master/...`, which went nowhere: bookdown expects a base URL
  and defaults the branch to `master`. The generated `index.Rmd` now records
  the full `https://github.com/owner/name` base and the project's own `branch`.
* When `renv::init()` failed, `create_publication()` rewrote the README and
  workflow to match, but left `index.Rmd` claiming that dependencies were
  pinned in `renv.lock`. It is now rewritten too.

## Validation

* `check_publication()` reports whether `index.Rmd` declares an output format,
  the one render failure bookdown does not report: without one it falls back to
  `gitbook` and produces a site that looks built but is not the one the project
  asked for.
* The bibliography is checked at the path `index.Rmd` declares, rather than
  assumed to be `references.bib` in the root.
* Unregistered chapter files are detected in the project root, ignoring
  `index.Rmd` and bookdown's merged intermediate.

# alberdilabr 0.1.2

* `create_publication()` defaults `path` to the working directory, matching the
  rest of the package and the way R is normally run: from the root of the
  repository that will hold the publication.
* `create_publication()` no longer requires an empty directory. It refuses only
  when a file it would write is already present, and reports every collision
  before writing anything, so scaffolding into an existing repository -- its
  `.git/`, its licence, its sources -- is now the expected way to use it.
* A failed creation still leaves no trace. When the project was scaffolded into
  a directory that already existed, only the files and directories the scaffold
  itself created are removed.

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
