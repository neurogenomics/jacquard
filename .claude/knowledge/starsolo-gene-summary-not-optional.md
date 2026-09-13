---
name: starsolo-gene-summary-not-optional
type: gotcha
---
# `--soloFeatures GeneFull` alone breaks the vendored `star/starsolo` module

STARsolo writes `Solo.out/<feature>/` for each requested feature and **no `Solo.out/Gene/`** unless
`Gene` is explicitly among them. The vendored module declares

```groovy
tuple val(meta), path('*/Gene/Summary.csv'), emit: summary   // no optional: true
```

so any `--soloFeatures` value that omits `Gene` fails the task with
`Missing output file(s) '*/Gene/Summary.csv' expected by process`. Vendored modules must not be
hand-edited, so `conf/modules.config` always prepends `Gene`:

```groovy
"--soloFeatures ${(['Gene'] + params.solo_features.tokenize()).unique().join(' ')}"
```

Asking for the extra feature is side-effect-free — `Gene/Features.stats` is byte-identical with and
without `GeneFull` — and costs no measurable runtime at test scale.

**MultiQC only parses `*Log.final.out`**, so extra feature trees reach the published output but never
the report.

Valid `--soloFeatures` values, probed against STAR 2.7.11b in the carmack container: `Gene`, `SJ`,
`GeneFull`, `GeneFull_ExonOverIntron`, `GeneFull_Ex50pAS`, `Velocyto`. Note `Velocyto` **is**
accepted despite being absent from `STAR --help`; `Transcript3p` is marked not-supported upstream.
