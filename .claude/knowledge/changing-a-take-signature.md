---
name: changing-a-take-signature
type: way-of-working
---
# Changing a subworkflow's `take:` breaks every test that instantiates it

Adding an input to a named workflow's `take:` block is a **breaking change to every `.nf.test` that
calls it**, and Nextflow reports it only at runtime:

```
ERROR ~ Workflow `CARMACK_READPREP` declares 3 input channels but 2 were given
```

This shipped once here: `--stop_after` added a third `take:` to `CARMACK_READPREP` and 13 call
sites across 4 test files went red — invisible because verification ran only the **pipeline-level**
`tests/` directory and `just smoke`, which drive `main.nf` and never instantiate a subworkflow
directly.

**So: after changing a `take:` signature, run the subworkflow and module suites, not just
`tests/`.** `grep -rln '<WORKFLOW_NAME>' --include='*.nf.test'` finds every call site; each needs
the new input added positionally.

The same trap applies to a task brief: asking an agent to verify with `nf-test test tests/` alone is
not enough whenever the change touches a `take:` block, an `emit:` name, or a module's `input:`.
