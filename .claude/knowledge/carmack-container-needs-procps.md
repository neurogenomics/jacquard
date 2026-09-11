---
name: carmack-container-needs-procps
type: gotcha
---
# The carmack container must have `procps` layered on

carmack's own image (`external/carmack/Dockerfile`, micromamba on Debian) ships no `procps`.
Nextflow's generated `.command.run` **hard-exits 1** when `ps` is missing:

```
nxf_trace_linux() { command -v ps &>/dev/null || { >&2 echo "Command 'ps' required by nextflow to collect task metrics cannot be found"; exit 1; } ... }
```

`nextflow.config` enables `trace`/`report`/`timeline`, so `nxf_trace` always runs and **every**
carmack process fails — with a misleading `exit: 1` against the carmack command, even though
`docker run … carmack --version` succeeds by hand.

`just carmack-image` therefore builds the submodule as `…:local-base`, then layers `procps` on via
`containers/carmack-procps.Dockerfile` to produce `…:local`. The pinned submodule is never patched.
The real fix belongs upstream in carmack; until then any new carmack-based image needs this layer.
