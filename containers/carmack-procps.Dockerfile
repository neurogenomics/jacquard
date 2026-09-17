# Nextflow's task-metrics wrapper hard-exits when `ps` is missing (.command.run -> nxf_trace_linux),
# and the template enables trace/report/timeline, so every carmack process would fail even though
# carmack itself succeeds. carmack's image is micromamba-on-Debian and ships no procps. Adding it in
# a thin layer here keeps the pinned submodule untouched; the upstream fix belongs in carmack.
ARG CARMACK_BASE
FROM ${CARMACK_BASE}

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*
USER $MAMBA_USER
