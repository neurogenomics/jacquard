# Knowledge index

Durable, hard-won facts about this pipeline — one file per fact, linked from here.
Add an entry when something cost real time to work out and would cost it again.

- [A container without procps breaks every task](carmack-container-needs-procps.md) — Nextflow exits 1 without `ps`, blaming the wrong command; carmack ships it since `24f7fbb`.
- [carmack image tag and submodule pin move together](carmack-image-pin.md) — modules name `sha-<pin>`; bump the gitlink and every tag at once, or snapshots fail on the version header.
- [nf-test samplesheet paths](nf-test-samplesheet-paths.md) — launchDir differs under nf-test; use `Fixtures.absolutise`.
- [Never snapshot lines that can be blank](nf-test-snapshot-blank-lines.md) — nf-test resolves `''` as a directory and inlines its listing.
- [nf-test md5 decompresses gzip](nf-test-md5-decompresses-gzip.md) — content-identical `.gz` files hash the same; use raw bytes for byte-identity.
- [Nextflow 26 parser and warnings](nextflow-26-parser-and-warnings.md) — `log.warn` is invisible to nf-test; no top-level `import` in `.nf`.
- [Nextflow 26 script params scope](nextflow-26-script-params-scope.md) — `params.x =` in `main.nf` is `null` inside included subworkflows.
- [STARsolo Gene/Summary.csv is not optional](starsolo-gene-summary-not-optional.md) — `--soloFeatures` must always include `Gene`.
- [nft-bam getSamLines truncates](nft-bam-getsamlines-truncates.md) — never count BAM records under nf-test; assert set equality or read the tool's log.
- [Changing a take: signature](changing-a-take-signature.md) — breaks every nf-test that instantiates it; `tests/` alone will not catch it.
- [MultiQC report_section_order sorts ascending](multiqc-report-section-order.md) — lower renders earlier; take section ids from a real run.
- [A `.*:SUBWORKFLOW:PROCESS` selector matches in a run but not under nf-test](withname-selector-under-nf-test.md) — drop the colon after `.*`.
- [Toolchain PATH in non-interactive shells](toolchain-path-noninteractive.md) — `conda activate` fails; prefix the env's bin.
