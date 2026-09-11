# Knowledge index

Durable, hard-won facts about this pipeline — one file per fact, linked from here.
Add an entry when something cost real time to work out and would cost it again.

- [carmack container needs procps](carmack-container-needs-procps.md) — every carmack process exits 1 without it, blaming the wrong command.
- [nf-test samplesheet paths](nf-test-samplesheet-paths.md) — launchDir differs under nf-test; use `Fixtures.absolutise`.
- [Never snapshot lines that can be blank](nf-test-snapshot-blank-lines.md) — nf-test resolves `''` as a directory and inlines its listing.
- [Toolchain PATH in non-interactive shells](toolchain-path-noninteractive.md) — `conda activate` fails; prefix the env's bin.
