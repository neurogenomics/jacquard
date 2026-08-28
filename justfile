set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

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
    source .venv/bin/activate && black --check lib/ && isort --check-only lib/ && ruff check lib/

# Autoformat Python
fmt:
    source .venv/bin/activate && black lib/ && isort lib/ && ruff check --fix lib/

# nf-core pipeline linting
nf-lint:
    source .venv/bin/activate && nf-core pipelines lint

# nf-test suite
nf-test *ARGS="":
    nf-test test {{ARGS}}

# Smoke-run the pipeline against the bundled test profile
smoke OUTDIR="results_test":
    nextflow run . -profile test,docker --outdir {{OUTDIR}}

# Sync the nf-core template into the TEMPLATE branch
sync:
    source .venv/bin/activate && nf-core pipelines sync
