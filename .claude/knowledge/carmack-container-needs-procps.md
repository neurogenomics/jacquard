---
name: carmack-container-needs-procps
type: gotcha
---

# Any container running a Nextflow task must ship `procps`

Nextflow's generated `.command.run` **hard-exits 1** when `ps` is missing:

```
nxf_trace_linux() { command -v ps &>/dev/null || { >&2 echo "Command 'ps' required by nextflow to collect task metrics cannot be found"; exit 1; } ... }
```

`nextflow.config` enables `trace`/`report`/`timeline`, so `nxf_trace` always runs and every task in
such an image fails — with a misleading `exit: 1` against the tool's own command, even though
`docker run … <tool> --version` succeeds by hand.

As of carmack `24f7fbb` (2026-09-27) carmack's image installs `procps-ng` itself, so
jacquard's old `containers/carmack-procps.Dockerfile` layer is gone. Watch for this in any _other_
minimal image (micromamba, alpine, distroless) wired into a local module.
