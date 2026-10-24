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

## Engineering standards

These apply to every agent (Codex, Claude, others) and every person, and they come before new feature work. Open clean-up work is in milestone *M0 — Engineering foundations* (#61 #62).

**Small changes, merged often**
- One issue, one short-lived branch off the default branch in its own worktree, one PR. Aim for about 400 changed code lines or fewer, excluding generated files and lockfiles. One purpose per PR. Merge within a day or two.
- No long-lived integration branches, and no stacks deeper than about 3 PRs. A PR open more than 7 days gets rebased, split or closed.
- The default branch always builds and passes tests.

**No data in git**
- Git holds code, configs, schemas and tiny test fixtures (under about 1 MB each). Raw or processed data, large outputs, binaries, notebooks with big outputs, HPC logs and build artefacts live in external storage (Imperial RDS project space, an object store, or release assets). A small manifest stays in git: path or URL, size, sha256, provenance.
- A large-file check runs on pre-commit and in CI. Don't bypass it; add a justified allowlist entry instead.
- Never rewrite published history, force-push, or delete data without Nathan's explicit OK.

**Issue-driven**
- Every PR links an issue in a milestone. Update the issue when work starts and when it lands. Close it with `Closes #N` only when its acceptance criteria are verified. Split any remainder into a new issue rather than leaving the original open.
- Consolidate duplicates. Don't let open issues pile up.

**Checks that actually run**
- CI, or the local pre-merge script when CI is unavailable, runs lint, type checks and tests on every change. Use the pinned Nextflow/nf-test versions and Python via uv.lock. Commit lock files.
- Never weaken, skip or delete tests to go green.

**Tests over paperwork**
- Progress means working, user-visible features verified by tests or end-to-end checks, not record, receipt or evidence commits. At most 1 in 5 commits on a PR may be process documentation. Prefer one concise STATUS.md over growing logs.
- Honest data: no placeholder or mock numbers presented as real. Synthetic data is visibly labelled.

**Review and hygiene**
- A different agent or model reviews each PR before merge (for example, Codex reviews Claude and Claude reviews Codex). Findings become issues. Agents don't merge their own PRs without that review.
- Remove worktrees and branches once merged or abandoned. Each agent has at most 3 active worktrees per repo. Close superseded PRs. Everything is pushed to the remote.
- Repository visibility is changed only by Nathan. Never add credentials, personal data or unpublished lab data: this repository is public.

