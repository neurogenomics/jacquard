---
name: nextflow-26-parser-and-warnings
type: gotcha
---
# Nextflow 26: `log.warn` is invisible to nf-test, and top-level `import` is rejected

**`log.warn` never reaches `workflow.stdout`.** Nextflow 26 keeps warnings off the console, so an
nf-test asserting on a warning finds nothing — while `error()` *is* reported there, which makes the
asymmetry easy to misread as "the warning was never emitted". Read the run's own log instead:
`tests/lib/Fixtures.warnings(workDir)` parses `meta/nextflow.log`, a sibling of the test `$workDir`.

This matters wherever a warning is the *specified behaviour* rather than noise — in this pipeline a
gate-dropped arm and a pure-scRNA run are both required to warn and proceed, so the warning is part
of the contract and has to be asserted.

**The strict parser rejects a top-level `import`** in a `.nf` file. Use the fully-qualified name
inline instead:

```groovy
def dist = new groovy.json.JsonSlurper().parse(stats_json)
```
