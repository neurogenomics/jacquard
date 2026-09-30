# neurogenomics/jacquard

scMultiome pipeline, built on the nf-core template (tools 4.1.0).

## Environment

The conda env `jac` carries the _runtime_ toolchain; the uv venv `.venv` carries _Python_.

```bash
conda activate jac   # python 3.14, openjdk 25, nextflow 26.04.6, uv, just
just dev             # creates/refreshes .venv and drops you into it
```

Never install Python packages into `jac` — they belong in `pyproject.toml` and reach `.venv`
through `uv sync`. `uv.lock` is committed and authoritative; regenerate it with `uv lock`, never
by hand.

## Commands

| Command                  | What it does                                                       |
| ------------------------ | ------------------------------------------------------------------ |
| `just dev`               | Create/refresh `.venv`, install deps + the editable `core` package |
| `just test`              | Python unit tests (`lib/core/tests`)                               |
| `just lint` / `just fmt` | black + isort + ruff, check / write                                |
| `just nf-lint`           | `nf-core pipelines lint`                                           |
| `just nf-test`           | nf-test suite                                                      |
| `just smoke`             | `nextflow run . -profile test,docker`                              |
| `just sync`              | Pull template updates into the `TEMPLATE` branch                   |

## Layout

- `main.nf`, `workflows/`, `subworkflows/`, `modules/` — the Nextflow pipeline.
- `lib/core/` — the Python package Nextflow processes import as `core`. Installed editable, so
  `package-dir = {"" = "lib"}` in `pyproject.toml` is load-bearing; `lib/core/tests/` guards it.
- `conf/` — profiles and per-module resource config.

## carmack

carmack is a separate repo, [`neurogenomics/carmack`](https://github.com/neurogenomics/carmack),
vendored as the `external/carmack` submodule. Changes to carmack's behaviour land there first;
jacquard only bumps the pin and does its own wiring.

The pipeline runs carmack's published image, never a local build. Every carmack-derived module
declares `ghcr.io/neurogenomics/carmack:sha-<7>`, and `<7>` **must be the submodule's pin**. Keep
the two in lockstep: a bump moves the gitlink and every `container` tag in the same commit. carmack
publishes `sha-<7>` only for commits that reach its `main`, so pin the tip of `main` once its
publish run has finished. Every carmack stats file records `0.0.0+<sha>`, so snapshots move with
the pin. `just carmack-image` and the nf-test CI action both fail when a tag and the pin disagree.
The full bump procedure is in `.claude/knowledge/carmack-image-pin.md`.

## Comments

This is a production pipeline, and its comments are read by people who were not present when the
code was written. A comment must stand on its own: give the reason in terms of the chemistry, the
data or the tool's behaviour, and quote the measurement that settled it where one exists.

Do not appeal to context the reader has no access to. No references to a "manual analysis", a
previous script-based pipeline, an epic, a PR, a review, a ticket, or what someone decided in a
conversation. If a number came from somewhere, state the number and what it measures, not where it
was produced.

```groovy
// Bad  — the reader cannot check any of this
'--length_required 25',  // the floor the manual scTIP analysis used

// Good — the reason is in the comment
// Below 25 bases a Tn5 insert no longer places uniquely often enough to be worth aligning, so a
// pair trimmed past that floor is dropped rather than carried into bowtie2 as a multi-mapper.
'--length_required 25',
```

## Branches

`main` is the release branch, `dev` the integration branch, `TEMPLATE` the nf-core sync base.
PRs target `dev`; `.github/workflows/branch.yml` enforces that only `dev` and `patch` branches
may PR into `main`.

## Versioning

release-please owns the version. Use [Conventional Commits](https://www.conventionalcommits.org/);
pushes to `main` refresh a Release PR, and merging it cuts the tag. `version.txt` and
`nextflow.config`'s `manifest.version` (marked `x-release-please-version`) bump in lockstep — do
not edit either by hand, and do not hand-edit `CHANGELOG.md`.
