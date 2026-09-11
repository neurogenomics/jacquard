---
name: toolchain-path-noninteractive
type: how-to
---
# Reaching the `jac` toolchain from a non-interactive shell

`conda activate jac` fails in a non-interactive shell (`CondaError: Run 'conda init' before 'conda
activate'`), so `nextflow`, `nf-test`, `just`, `uv` and `nf-core` are all "not found" despite being
installed. Prefix instead:

```bash
export PATH="/home/hiru/data/miniforge3/envs/jac/bin:$PATH"
```

`nf-core` lives in the uv venv, not `jac`: `source .venv/bin/activate` for it. `docker` is on the
system PATH already.
