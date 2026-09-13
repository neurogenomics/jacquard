---
name: nextflow-26-script-params-scope
type: gotcha
---
# A script-level `params.x = …` in `main.nf` is invisible to included scripts

Nextflow 26: assigning a param at script level in `main.nf` does **not** make it visible inside an
included workflow or subworkflow — it reads back as `null` there, even when the assigned value is
non-null. Reproduced in isolation.

This makes the nf-core template's own hook silently dead for anything outside `main.nf`:

```groovy
params.fasta = getGenomeAttribute('fasta')   // main.nf — invisible downstream
```

The symptom is a `WARN: Access to undefined parameter '<name>'` and a null reference somewhere far
from the assignment.

Declare such params in `nextflow.config` (globally visible) and resolve any igenomes fallback at the
call site, passing the value down through `take:` rather than reaching for `params` inside the
subworkflow:

```groovy
JACQUARD(..., params.fasta ?: getGenomeAttribute('fasta'), ...)
```

This is the same discipline the `chemistry` param already follows in this pipeline.
