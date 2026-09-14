---
name: nf-test-samplesheet-paths
type: gotcha
---

# Pipeline-level nf-tests need absolutised samplesheet paths

nf-schema resolves a samplesheet's file fields against **launchDir**. For `nextflow run .` / `just
smoke` from the repo root that is the repo root, so the committed
`tests/data/samplesheet_test.csv`'s repo-relative FASTQ paths resolve. Under nf-test, launchDir is
`.nf-test/tests/<hash>/`, and they do not — the run dies in parameter validation with
`the file or directory 'tests/data/…' does not exist`, before any process is submitted.

Things that do **not** work (both verified empirically against nf-test 0.9.5):

- `config { stage { symlink "tests/data" } }` in `nf-test.config` — not applied to
  `nextflow_pipeline` tests.
- `${projectDir}` inside the CSV — config interpolation does not reach samplesheet contents.

The working pattern: `libDir = "tests/lib"` in `nf-test.config`, and every pipeline-level test does

```groovy
when { params { input = Fixtures.absolutise("$baseDir", "$outputDir"); outdir = "$outputDir" } }
```

`Fixtures.absolutise` rewrites the committed sheet's relative paths to absolute in `$outputDir`, so
the committed sheet stays the single source of truth. Note `setup {}` is only valid **inside** a
`test {}` block, and `String[].withIndex()` needs a `.toList()` first in nf-test's Groovy.

Related: the nf-core template's bare `data/` in `.gitignore` silently swallows `tests/data/`, so
fixtures are never committed. `!tests/data/` un-ignores them, and `.gitignore` then needs a
`files_unchanged` exemption in `.nf-core.yml`.

Also: `prek run --all-files` only covers **git-tracked** files, so a brand-new file you have not
`git add`ed yet is silently skipped and then fails in CI once committed. Stage before you run it.
