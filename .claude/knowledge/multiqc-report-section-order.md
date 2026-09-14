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
