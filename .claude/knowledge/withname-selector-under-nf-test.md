---
name: withname-selector-under-nf-test
type: gotcha
---

# A `.*:SUBWORKFLOW:PROCESS` selector matches in a run but not under nf-test

Nextflow full-regex-matches a colon-bearing `withName:` selector against the **entire** qualified
process name, and that name is shorter when an nf-test instantiates a subworkflow directly:

| Context                                 | Qualified name                                    |
| --------------------------------------- | ------------------------------------------------- |
| `nextflow run .`                        | `NEUROGENOMICS_JACQUARD:JACQUARD:SCTIP_ARM:FASTP` |
| `nextflow_workflow` test of `SCTIP_ARM` | `SCTIP_ARM:FASTP`                                 |

So `'.*:SCTIP_ARM:FASTP'` — the form that fixes the well-known "partial path matches nothing" trap —
matches the run and **not** the test: the `.*:` demands a preceding colon the test's name has not got.
The process then runs on stock defaults while the test passes on everything except the arguments, and
Nextflow only warns (`no process matching config selector`) and exits 0.

Write `withName: '.*SCTIP_ARM:FASTP'` — no colon after `.*` — so one selector covers both. It is still
a full-path regex, so it cannot leak onto a sibling arm the way a bare `withName: 'FASTP'` would.

Assert the arguments off the tool's own record of its command line (fastp writes `command` into its
JSON), never off the selector having been written.
