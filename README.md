# alberdilabr

<!-- badges: start -->
[![R-CMD-check](https://github.com/alberdilab/alberdilabr/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/alberdilab/alberdilabr/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Create reproducible, publication-ready GitHub Pages websites from structured
R Markdown projects.

```r
create_publication(title = "My Analysis", author = "Jane Doe")
add_chapter("Sensitivity analysis")
preview_publication()
```

`create_publication()` scaffolds into the working directory by default, which
is normally the root of the repository that will hold the publication. Pass a
`path` to create the project elsewhere. Either way it refuses to overwrite a
file that is already there, so an existing repository -- its `.git/`, its
licence, whatever else it came with -- is safe to scaffold into.

alberdilabr scaffolds the project, keeps chapter files and their ordering in
step, validates the result, and wires up deployment. Rendering belongs to
[bookdown](https://bookdown.org), dependency pinning to
[renv](https://rstudio.github.io/renv/), and deployment to GitHub Actions.

**The project you get is an ordinary bookdown project.** It builds with
`bookdown::render_book()` whether or not this package is installed. There is no
custom output format and no package-specific machinery in the generated
sources.

## Installation

```r
# install.packages("pak")
pak::pak("alberdilab/alberdilabr")
```

## What you get

```text
my-analysis/
├── my-analysis.Rproj
├── index.Rmd              landing page and shared YAML front matter
├── _bookdown.yml          chapter order (authoritative) and output directory
├── _output.yml            bookdown::bs4_book configuration
├── README.md
├── references.bib
├── renv.lock              pinned package versions
├── .Rprofile
├── .gitignore
├── chapters/
│   ├── 01-introduction.Rmd
│   ├── 02-methods.Rmd
│   ├── 03-results.Rmd
│   └── 04-discussion.Rmd
├── R/
│   └── setup.R            options and libraries shared by every chapter
├── data/
├── figures/
├── assets/
│   └── style.css
└── .github/
    └── workflows/
        └── publish.yml    renders and deploys to GitHub Pages
```

Push to `main` and the workflow renders the book and publishes `_site/` to
GitHub Pages. Rendered HTML is never committed. The one manual step is enabling
Pages: **Settings → Pages → Build and deployment → Source → GitHub Actions**.

## The API

| Function | Purpose |
| --- | --- |
| `create_publication()` | Scaffold a complete project |
| `add_chapter()` | Create a chapter and register it |
| `remove_chapter()` | Unregister a chapter, optionally deleting it |
| `move_chapter()` | Reorder chapters and renumber the files |
| `preview_publication()` | Live-reloading local preview |
| `render_publication()` | Full production build into `_site/` |
| `check_publication()` | Validate the project |
| `use_github_publication()` | Add or refresh the Pages workflow |

## Chapter management

Chapters are numbered files in `chapters/`, listed explicitly in
`_bookdown.yml`. Explicit ordering means the reading order is a fact recorded in
one place rather than an accident of filename sorting.

Every mutating operation keeps the files and the configuration consistent:

```r
add_chapter("Study design", after = "introduction", template = "methods")
move_chapter("discussion", after = "results")
remove_chapter("appendix", delete_file = FALSE)
```

A chapter's slug is its identity, and it appears in three places that must
agree: the filename, the `rmd_files` entry, and the `{#slug}` heading anchor
that bookdown turns into the page's URL and cross-reference target.
`check_publication()` reports drift between them.

## Validation

```r
check_publication()
```

Reports on:

- **Structure** — required files and directories, readable configuration,
  registered chapters that exist, chapter files that nothing references.
- **Documents** — exactly one top-level heading per chapter, unique heading
  identifiers, unique knitr chunk labels, captioned figures that cannot be
  cross-referenced, sequential numbering.
- **Reproducibility** — `renv.lock` presence and whether it records everything
  needed to render. No network access.
- **Publishing** — the workflow exists, and the directory it uploads matches the
  one bookdown writes.

`check_publication(render = TRUE)` adds a full build as an integration test.

## License

MIT
