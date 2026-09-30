set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# The image every carmack-derived module declares. carmack's CI publishes it on each push to main;
# the external/carmack submodule records which of those commits the snapshots were taken against.
CARMACK_IMAGE := "ghcr.io/neurogenomics/carmack:main"

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

# Pull the carmack image the modules run. `:main` moves with every push to carmack's main and
# docker never re-pulls a tag it already holds, so without the pull a stale local copy would run.
# Every carmack stats file opens with `# Carmack version: 0.0.0+<sha>` and the snapshots record the
# submodule pin's sha, so an image built from any other commit fails every carmack snapshot. The
# recipe stops on that mismatch rather than letting nf-test report it as forty unrelated diffs.
carmack-image:
    #!/usr/bin/env bash
    set -euo pipefail
    docker pull -q {{CARMACK_IMAGE}} >/dev/null
    image=$(docker run --rm {{CARMACK_IMAGE}} carmack --version 2>/dev/null | tail -1 | sed 's/.*+//')
    pin=$(git ls-files -s external/carmack | cut -d' ' -f2 | cut -c1-7)
    if [ "$image" != "$pin" ]; then
        echo "{{CARMACK_IMAGE}} is carmack $image but external/carmack pins $pin." >&2
        echo "Bump the submodule to carmack's main and stage it (git add external/carmack)." >&2
        exit 1
    fi
    echo "{{CARMACK_IMAGE}} is carmack $image, matching the submodule pin."

# Smoke-run the pipeline against the bundled test profile
smoke OUTDIR="results_test": carmack-image
    nextflow run . -profile test,docker --outdir {{OUTDIR}}

# Sync the nf-core template into the TEMPLATE branch
sync:
    source .venv/bin/activate && nf-core pipelines sync
