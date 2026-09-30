set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# The image every carmack-derived module declares: carmack's CI publishes `sha-<7>` for each tested
# commit on its main and never moves it, so the tag names the external/carmack pin exactly. Read
# from the index rather than the submodule's working tree, so a bump counts once it is staged.
CARMACK_PIN := `git ls-files -s external/carmack | cut -d' ' -f2 | cut -c1-7`
CARMACK_IMAGE := "ghcr.io/neurogenomics/carmack:sha-" + CARMACK_PIN

default: dev

# Create/refresh the uv venv and drop into a shell with it active
dev:
    if [ ! -d .venv ]; then uv venv .venv; fi
    source .venv/bin/activate && \
        uv sync --group dev && \
        uv pip install -e . && \
        python -V && which python && exec $SHELL

# Python unit tests
test:
    source .venv/bin/activate && python -m pytest -v

# Python linters
lint:
    source .venv/bin/activate && black --check bin/ lib/ && isort --check-only bin/ lib/ && ruff check bin/ lib/

# Autoformat Python
fmt:
    source .venv/bin/activate && black bin/ lib/ && isort bin/ lib/ && ruff check --fix bin/ lib/

# nf-core pipeline linting
nf-lint:
    source .venv/bin/activate && nf-core pipelines lint

# nf-test suite. --profile=+docker mirrors CI (.github/actions/nf-test/action.yml:65);
# nf-test.config's bare "test" profile enables no container engine, so containerised
# modules would otherwise resolve against the host PATH.
nf-test *ARGS="": carmack-image
    nf-test test --profile=+docker {{ARGS}}

# Check every module names the pinned carmack image, then pull it. Every carmack stats file opens
# with `# Carmack version: 0.0.0+<sha>` and the snapshots record the pin's sha, so a module left on
# an older tag after a bump fails its snapshots with no hint of the cause. A failed pull means the
# pin has no published image: carmack publishes only commits that reach its main.
carmack-image:
    #!/usr/bin/env bash
    set -euo pipefail
    tags=$(grep -rhoE 'ghcr\.io/neurogenomics/carmack:[A-Za-z0-9._-]+' modules/ conf/ | sort -u)
    if [ "$tags" != "{{CARMACK_IMAGE}}" ]; then
        echo "external/carmack pins {{CARMACK_PIN}}, but the modules name:" >&2
        echo "$tags" | sed 's/^/  /' >&2
        echo "Every carmack container directive must be {{CARMACK_IMAGE}}." >&2
        exit 1
    fi
    if ! docker pull -q {{CARMACK_IMAGE}} >/dev/null; then
        echo "{{CARMACK_IMAGE}} is not published; pin a commit on carmack's main." >&2
        exit 1
    fi
    echo "Modules and external/carmack agree on {{CARMACK_IMAGE}}."

# Smoke-run the pipeline against the bundled test profile
smoke OUTDIR="results_test": carmack-image
    nextflow run . -profile test,docker --outdir {{OUTDIR}}

# Sync the nf-core template into the TEMPLATE branch
sync:
    source .venv/bin/activate && nf-core pipelines sync
