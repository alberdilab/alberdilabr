# {{{title}}}

{{{description}}}

Authored by {{{author}}}.

This is a [bookdown](https://bookdown.org) publication project. The rendered
website is built from the R Markdown sources in this repository and published to
GitHub Pages automatically.

## Repository structure

```text
index.Rmd            landing page and shared YAML front matter
_bookdown.yml        chapter order (authoritative) and output directory
_output.yml          HTML output format (bookdown::bs4_book)
chapters/            one .Rmd per chapter, numbered in reading order
R/setup.R            options, libraries and helpers shared by all chapters
data/                input data
figures/             generated figures
assets/style.css     custom CSS
references.bib       bibliography
.github/workflows/   GitHub Actions workflow that renders and deploys the site
```

## Building locally

```r
bookdown::render_book("index.Rmd")
```

The site is written to `_site/`. Open `_site/index.html` to read it.

If you have the `alberdilabr` package installed you can also use its helpers:

```r
alberdilabr::preview_publication()   # render and serve with live reload
alberdilabr::render_publication()    # one-off production render
alberdilabr::check_publication()     # validate project structure
alberdilabr::add_chapter("Sensitivity analysis")
```

These are conveniences. The project is a standard bookdown project and renders
without them.

{{#renv}}
## Reproducibility

R package versions are pinned with [renv](https://rstudio.github.io/renv/).
After cloning, restore the environment with:

```r
renv::restore()
```

When you add or remove packages, record the change with `renv::snapshot()` and
commit the updated `renv.lock`.
{{/renv}}
{{^renv}}
## Reproducibility

This project does not currently pin its R package versions. To add a lockfile:

```r
renv::init()
```

Then update `.github/workflows/publish.yml` to restore from it with
`r-lib/actions/setup-renv@v2`.
{{/renv}}

## Publishing

Pushing to `{{{branch}}}` triggers `.github/workflows/publish.yml`, which renders the
book and deploys `_site/` to GitHub Pages.

Before the first deployment, enable Pages for the repository:
**Settings → Pages → Build and deployment → Source → GitHub Actions**.

Rendered HTML is not tracked in Git.
