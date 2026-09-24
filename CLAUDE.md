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
| `just metro`             | Re-render the metro diagram from `docs/images/jacquard_metro.mmd`  |
| `just sync`              | Pull template updates into the `TEMPLATE` branch                   |

## Metro diagram

`docs/images/jacquard_metro.svg` — the figure `README.md` embeds — is generated from
`docs/images/jacquard_metro.mmd` by [nf-metro](https://github.com/seqeralabs/nf-metro), a uv tool
(`uv tool install nf-metro`) that lives outside the `jac` env. Never hand-edit the SVG.

**Any change to the process graph updates the `.mmd` and re-renders in the same commit.** That means
a module added, removed, renamed or re-wired; an arm's steps re-ordered; a subworkflow or
`include ... as` alias renamed, since `%%metro process:` lines match fully-qualified process names. A
parameter that only gates a step already on the map changes nothing — but the step it gates has to be
on the map.

```bash
just metro
```

To check the map against what a run actually executed, use `--processes` from a
`pipeline_info/execution_trace_*.txt`, not `--dag`: a `-preview -with-dag` export writes bare process
names and reports every station as stale.

```bash
awk -F'\t' 'NR>1{print $4}' <outdir>/pipeline_info/execution_trace_*.txt \
    | sed 's/ (.*)$//' | sort -u > /tmp/processes.txt
nf-metro check-mapping docs/images/jacquard_metro.mmd --processes /tmp/processes.txt
```

## Layout

- `main.nf`, `workflows/`, `subworkflows/`, `modules/` — the Nextflow pipeline.
- `lib/core/` — the Python package Nextflow processes import as `core`. Installed editable, so
  `package-dir = {"" = "lib"}` in `pyproject.toml` is load-bearing; `lib/core/tests/` guards it.
- `conf/` — profiles and per-module resource config.

## Branches

`main` is the release branch, `dev` the integration branch, `TEMPLATE` the nf-core sync base.
PRs target `dev`; `.github/workflows/branch.yml` enforces that only `dev` and `patch` branches
may PR into `main`.

## Versioning

release-please owns the version. Use [Conventional Commits](https://www.conventionalcommits.org/);
pushes to `main` refresh a Release PR, and merging it cuts the tag. `version.txt` and
`nextflow.config`'s `manifest.version` (marked `x-release-please-version`) bump in lockstep — do
not edit either by hand, and do not hand-edit `CHANGELOG.md`.
