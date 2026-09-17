---
name: multiqc-report-section-order
type: gotcha
---

# `report_section_order` sorts ascending — lower renders earlier

In MultiQC 1.35, a lower `order:` value renders **earlier**. Assuming higher-is-earlier produces an
exactly reversed report, which is easy to misread as the config not being applied at all. Confirmed
empirically in both directions.

This makes the nf-core template's inherited entries look wrong — `-1000`/`-1001`/`-1002` read as
"pin these first" but the sections appear at the end. Left alone here; just don't copy the pattern
expecting it to mean what it looks like.

Section ids must be the **real** ones, so take them from an actual run rather than deriving them
from payload names: `<h3 id="…">` in `multiqc_report.html`, cross-checked against
`multiqc_data.json`'s `report_plot_data` key order and the `multiqc_data/multiqc_*_plot.txt`
filenames. A `generalstats` payload has no section at all — it goes to the General Statistics table —
so a stage's payload count is not its section count (carmack: 13 payloads, 9 sections).

Assert order on `report_plot_data`'s key order, which is insertion-ordered by report order. Note
`.keySet().findAll{}` returns a `LinkedHashSet`, which never `==` a List — call `.toList()` first.
Same family as the `String[].withIndex()` trap in [[nf-test-snapshot-blank-lines]].

## `order:` does not place a module section relative to custom content

Measured on MultiQC 1.35 with this pipeline's report: giving the `fastp` module section **any**
positive `order:` — 999, 1005, 1011, 2000 all alike — pins it to the very top of the report, ahead of
the carmack custom-content sections ordered 1001–1010, while a negative value or no entry leaves it in
its default place near the end. The number is not comparable across the two kinds of section.

Use `after:` for relative placement instead:

```yaml
report_section_order:
  fastp:
    after: arm_gate
```

`after: arm_gate` lands fastp immediately after the last carmack section; `after:` naming a
custom-content id (`carmack_prepare_target_distribution`) or a module anchor (`bowtie2`) did nothing at
all — silently, as an unknown key always does. Probe candidates by re-running MultiQC over the staged
inputs in the MULTIQC task's work directory rather than by re-running the pipeline.
