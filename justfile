set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# carmack is vendored as a submodule; this tag is built locally from it.
CARMACK_IMAGE := "ghcr.io/crick-pipelines-stp/carmack:local"

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

# Build carmack's container from the pinned submodule, then layer on procps (see
# containers/carmack-procps.Dockerfile for why).
carmack-image:
    git submodule update --init external/carmack
    docker build -t {{CARMACK_IMAGE}}-base \
        --build-arg CARMACK_VERSION=0.0.0+$(git -C external/carmack rev-parse --short HEAD) \
        external/carmack
    docker build -t {{CARMACK_IMAGE}} \
        --build-arg CARMACK_BASE={{CARMACK_IMAGE}}-base \
        -f containers/carmack-procps.Dockerfile containers

# Smoke-run the pipeline against the bundled test profile
smoke OUTDIR="results_test": carmack-image
    nextflow run . -profile test,docker --outdir {{OUTDIR}}

# Re-render docs/images/jacquard_metro.svg from its .mmd source. Run whenever the
# process graph changes; see CLAUDE.md. nf-metro is a uv tool, not part of the jac env.
metro:
    nf-metro validate docs/images/jacquard_metro.mmd
    nf-metro render docs/images/jacquard_metro.mmd -o docs/images/jacquard_metro.svg

# Sync the nf-core template into the TEMPLATE branch
sync:
    source .venv/bin/activate && nf-core pipelines sync
