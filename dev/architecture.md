# Architecture and design decisions

Version 0.1. Each decision records what was chosen and why, so that a later
change is a deliberate reversal rather than an accident.

## Scope

The package owns **scaffolding, conventions, chapter management, validation and
developer experience**. It does not own rendering, dependency resolution or
deployment:

| Concern | Owner |
| --- | --- |
| Rendering | `bookdown` |
| Dependency reproducibility | `renv` |
| Deployment | GitHub Actions |
| Everything above | this package |

## D1. The generated project does not depend on this package

**Decision.** Generated projects contain only standard bookdown configuration.
No custom output format (`alberdilabr::publication_book`), no package-specific
YAML keys, no calls into this package from any generated source file.

**Why.** A publication outlives its tooling. If this package is abandoned,
unavailable on a collaborator's machine, or broken by an upgrade, the project
must still build. A custom output format would make the package a permanent
render-time dependency of every project it ever created.

**Enforcement.** `tests/testthat/test-render.R` renders a generated project with
`bookdown::render_book()` in a session where this package is never loaded.

**Cost.** Configuration is duplicated into every project rather than centralised
in the package, so a convention change does not propagate to existing projects.
That is the correct trade: existing projects keep working.

## D2. Package name

**Decision.** `alberdilabr`, the name of the repository the work was started in.

**Status.** Provisional and cheap to change: the name appears in `DESCRIPTION`,
`system.file()` calls in `R/templates.R`, and generated README text.

**Alternatives considered.** `pubcraft`, `bookforge`, `publish`, `rpublication`,
`scaffoldr`. A more descriptive name would suit a package published to CRAN;
`alberdilabr` suits a lab-internal package that may later grow beyond
publication scaffolding.

## D3. Explicit chapter ordering

**Decision.** `_bookdown.yml` lists every source file in `rmd_files`. Bookdown's
implicit alphabetical discovery is not used.

**Why.** Alphabetical discovery makes reading order an emergent property of
filenames, so a rename silently reorders the book and a stray `.Rmd` in
`chapters/` silently joins it. An explicit list makes order a recorded fact, and
makes "this file is not in the book" a detectable condition — which
`check_publication()` reports.

**Cost.** Two things must be kept in step. That is precisely what
`add_chapter()`, `move_chapter()` and `remove_chapter()` are for, and what
`check_publication()` verifies.

## D4. Slug as chapter identity

**Decision.** A chapter's slug appears in three places, which must agree: the
filename (`chapters/03-results.Rmd`), the `rmd_files` entry, and the heading
anchor (`# Results {#results}`).

**Why.** The heading anchor determines the page URL and is the target of every
`\@ref()` cross-reference. Deriving it from the same slug as the filename means
a chapter can be located from a link and vice versa. The numeric prefix carries
*order* only, never identity — that is why `move_chapter()` can renumber files
freely without breaking a single link.

`check_publication()` reports drift between filename slug and heading anchor as
a warning rather than an error, because a deliberate mismatch is legitimate when
preserving an already-published URL.

## D5. Transactional filesystem operations

**Decision.** Every mutating operation follows: validate → compute the complete
new state in memory → write files → write `_bookdown.yml` last, atomically → roll
back file writes on failure.

**Details.**

- `write_lines_atomic()` writes to a temporary file in the *destination
  directory* and renames it into place. Rename within a directory is atomic, so
  a reader never sees a truncated `_bookdown.yml`.
- `_bookdown.yml` is written last because it defines the project. A crash before
  that point leaves an unreferenced stray file, which `check_publication()`
  reports and which harms nothing. A crash *during* it is impossible.
- `renumber_chapter_files()` moves files through temporary names before moving
  them to their final ones. A direct rename would destroy a file whenever a
  reorder maps `01 → 02` and `02 → 01`.
- `remove_chapter()` parks the file in a temporary location rather than deleting
  it, so a failure during renumbering can put it back.
- `create_publication()` deletes the project directory if any step fails — but
  only if it created that directory.

## D6. Dependencies

**Imports** (all zero-dependency or base):

| Package | Why it earns its place |
| --- | --- |
| `cli` | Every error must be actionable. Structured conditions, bullets and hyperlinked `{.run}` calls are the feature, not decoration. |
| `fs` | Correct path handling and, critically, `file_move`/`file_temp` for the atomic-write and renumbering patterns. |
| `yaml` | `_bookdown.yml` and `_output.yml` must be read and written. Not optional. |
| `rlang` | Condition classes, `caller_env()` for errors that point at the user's call, `is_interactive()`. |
| `whisker` | Template substitution. See D7. |
| `stats`, `tools` | Base packages; declared because they are imported from. |

**Suggests.** `bookdown`, `rmarkdown`, `knitr` and `servr` are needed to
*render*, not to *scaffold*. Someone creating a project on a machine that will
never build it should not pay for them. They are gated at the point of use by
`check_suggested()`, which fails with an install command. `renv` likewise.

**Rejected.** `usethis` — see D8. `glue` — see D7. `commonmark` — see D9.
`gert`/`gh` — see D10. `jsonlite`: `renv.lock` is the only JSON the package
reads, and `renv::lockfile_read()` handles it when renv is present; a package
name scrape covers the case where it is not.

## D7. whisker, not glue, for templates

**Decision.** Templates use mustache (`{{{var}}}`) rendered by `whisker`.

**Why.** Templates are `.Rmd` files full of `{r setup, include = FALSE}` chunk
headers and `{#anchor}` heading attributes. `glue`'s `{}` delimiters would
require escaping every one of them, turning readable templates into noise.

**Known hazard.** whisker silently discards a placeholder whose closing
delimiter is immediately followed by `}`. So the natural way to write a heading
anchor —

```
# {{{title}}} {#{{{slug}}}}
```

— renders as `# Title {#`, with no error. This is delimiter-independent:
switching to `<% %>` does not help. It cost real debugging time during
development, and it fails *quietly*, which is worse than failing loudly.

**Mitigations.**

1. Templates receive a ready-made `anchor` variable (`"{#slug}"`) and write
   `# {{{title}}} {{{anchor}}}`, so no placeholder abuts a `}`.
2. `whisker_hazard()` scans every template before rendering and refuses one that
   contains the pattern, with an error explaining the fix. This protects anyone
   adding their own template.
3. `render_chapter_template()` asserts the rendered chapter actually contains
   its anchor.
4. A test asserts no shipped template trips the check.

GitHub Actions templates have the mirror-image problem — they are full of
`${{ secrets.GITHUB_TOKEN }}`, which whisker would interpolate away. They open
with `{{=<% %>=}}` to switch delimiters, so GitHub's syntax passes through
untouched. A test asserts `${{ secrets.GITHUB_TOKEN }}` survives.

## D8. Own template renderer, not `usethis::use_template()`

**Decision.** A ~20-line `use_template()` in `R/templates.R`.

**Why.** usethis resolves paths against a global "active project" and will
prompt to change it. That is the wrong model for a function whose entire job is
to populate a directory that is *not* the active project and must not become
one. Fighting that global state would cost more code than the renderer, and
would add a heavy dependency to save nothing.

## D9. A small fence-aware scanner, not a Markdown parser

**Decision.** `scan_rmd()` strips YAML front matter, tracks code fences, and
extracts headings, heading ids, chunk labels and `fig.cap` options by line.

**Why not `commonmark`?** A CommonMark parser does not know what a knitr chunk
header is. `` ```{r label, fig.cap="x"} `` is an opaque info string to it, so
chunk labels and figure captions — half of what the document checks look at —
would still need extracting by hand. It would also misparse: `#` comments inside
an R chunk are ATX headings to CommonMark, which is exactly the false positive
the checks must avoid.

The genuine fragility in a hand-rolled scanner is fence tracking, and that is
what the scanner actually implements. Tests cover R comments inside chunks,
plain fences, and YAML front matter.

**Boundary.** If checks ever need real inline Markdown structure — link
resolution, emphasis, tables — this decision should be revisited rather than
extended.

## D10. Git through the command line

**Decision.** `system2("git", ...)`, not `gert` or `usethis`.

**Why.** Anyone deploying to GitHub Pages already has git installed, so this
costs no dependency. The commands are ones the user can read in the source and
repeat by hand. Absence of git degrades to a warning and a still-valid project,
rather than an error.

## D11. renv is on by default and runs in a subprocess

**Decision.** `renv = TRUE` by default. It runs `renv::init()` via `Rscript` in a
separate process.

**Why a subprocess.** Called in-process, `renv::init()` rewrites the calling
session's library paths and loads a different set of packages underneath the
user. That is an unacceptable side effect for a scaffolding function.

**Why on by default.** The brief asks the default to favour reproducibility. A
project created without a lockfile tends never to acquire one.

**The cost, acknowledged.** `renv::init()` installs the project's dependencies
into a private library and takes minutes. This is the heaviest thing the package
does. It is mitigated by: an up-front message saying so; `renv = FALSE` for a
fast path; and graceful degradation when renv is not installed — a warning, and
a project that still renders and deploys.

**Honesty on failure.** When renv is requested but unavailable, the README and
workflow already written would describe a lockfile that does not exist. They are
rewritten to match reality (`rewrite_without_renv()`) rather than left lying.

**Revisit if.** Users routinely pass `renv = FALSE` to avoid the wait. The
alternative would be to scaffold renv's files and defer installation.

## D12. `_site/`, not `_book/`

**Decision.** `output_dir: _site`.

**Why.** It matches the brief and reads as a website rather than a book. The
value is not hardcoded anywhere: `render_publication()`, `preview_publication()`
and the workflow all read `output_dir` from `_bookdown.yml`, and
`check_publication()` verifies the workflow's upload path agrees with it. A user
who changes it gets a check failure until the workflow matches.

## D13. Workflow shape and action versions

**Decision.** Versions are taken from the actively maintained
`r-lib/actions/examples/bookdown-gh-pages.yaml`, verified against the GitHub API
during development: `actions/checkout@v6`, `actions/cache@v5`,
`actions/upload-pages-artifact@v5`, `actions/deploy-pages@v5`,
`r-lib/actions/*@v2`.

`actions/checkout@v7` and `actions/cache@v6` exist and are drop-in. The r-lib
set was preferred because those versions are integration-tested together against
R workflows, which is a stronger signal than "newest".

**`actions/configure-pages` is deliberately omitted.** It is needed to obtain a
base URL or to auto-enable Pages; bs4_book needs neither, and `deploy-pages`
works without it. The maintained r-lib example omits it too. Including it would
add a failure mode (it errors when Pages is not yet enabled) for no benefit.

**Two workflow variants.** `publish-renv.yml` uses
`r-lib/actions/setup-r@v2` with `r-version: renv` — which reads the R version
out of `renv.lock`, so CI matches the machine that made the lockfile — followed
by `setup-renv@v2`. `publish-simple.yml` installs packages unpinned and carries
a comment block explaining exactly how to migrate to the pinned variant.
`use_github_publication()` detects which is appropriate from the presence of
`renv.lock`.

**Concurrency** is `cancel-in-progress: false`: cancelling a half-finished Pages
deployment is worse than waiting for it.

## D14. Check results are data

**Decision.** `check_publication()` returns a data frame of
`category`/`status`/`message` with a `print()` method, rather than printing
directly.

**Why.** It makes the checks testable one at a time — the test suite asserts the
status of a specific check against a deliberately broken fixture — and lets
callers use the result programmatically (in CI, for instance).

**Bug worth remembering.** Messages are interpolated by cli as *values*
(`cli_alert_warning("{msg}")`), never as format strings. Check messages
legitimately contain braces — `{#id}`, chunk options — and passing them as
format strings caused cli to evaluate and swallow them.

Relatedly, `pub_abort()` forwards `.envir = caller_env()` to `cli_abort()`.
Without it, cli interpolates the message in the wrapper's frame and cannot see
the caller's locals.

## Known gaps in 0.1

- The renv path is not covered by an automated test, because a real
  `renv::init()` takes minutes. It has been exercised manually only.
- `preview_publication()` is a thin wrapper over `bookdown::serve_book()` and is
  not automatically tested, since it starts a server.
- No RStudio project template yet (D15).
- `check_publication()` does not verify that `\@ref()` targets resolve.

## D15. RStudio project template — designed for, not built

The eventual `File → New Project → Publication Project` template must call
`create_publication()` rather than reimplement it. The signature is already
compatible: all arguments are scalars with sensible defaults, which is what an
RStudio template widget can supply. Adding it means writing
`inst/rstudio/templates/project/create_publication.dcf` and a thin wrapper that
maps widget values onto the existing arguments. No change to the current API is
needed.
