# neurogenomics/jacquard: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

Every sample is prepared once, then fans out into one **scRNA arm** (target index `NONE`, written as `none` in file names) and one **scTIP arm** per target index the library carries. Arm outputs are named `<sample>.<tgidx>` throughout, so the two arms of a sample never share a directory or a MultiQC row.

```text
carmack/{extractbarcodes,extractumis,assigntargets,preparereads}/<sample>/
fastqc/                              raw R1 and R2
fastqc/prepared/<sample>.<tgidx>/    per arm, on the reads that arm aligns
fastp/<sample>.<tgidx>/              per arm, the trimming reports
star/<sample>.none/                  scRNA arm — Solo.out lives here
bowtie2/<sample>.<tgidx>/            scTIP arm — alignment log
umitools/<sample>.<tgidx>/           scTIP arm — UMI-deduplicated BAM
lineardedup/<sample>.<tgidx>/        scTIP arm — final BAM, linear duplicates collapsed
samtools/<sample>.<tgidx>/           scTIP arm — stats on the final BAM
multiqc/
pipeline_info/
```

### carmack read preparation

<details markdown="1">
<summary>Output files</summary>

- `carmack/extractbarcodes/<sample>/`: `*.r1_annotated.fastq.gz`, the barcode whitelist and rank plot (`*.bc_*`), and `*_mqc.json`.
- `carmack/extractumis/<sample>/`: `*.r1_umi.fastq.gz` and `*.umi_stats.txt`.
- `carmack/assigntargets/<sample>/`: `*.r1_tgidx.fastq.gz` and `*.tgidx_stats.txt`.
- `carmack/preparereads/<sample>/`
  - `scrna/*.none.{r1,r2,barcodes}.fastq.gz`: the scRNA arm's cDNA pair plus the synthesized corrected-barcode-and-UMI read.
  - `sctip/*.<tgidx>.r{1,2}.fastq.gz`: one read pair per target index.
  - `*.detected_targets.txt`, `*.prepare_stats.txt`, and one `*_mqc.json` per MultiQC payload.

</details>

Only R1 goes through the chain — it carries the barcode, UMI and target index — and the raw R2 rejoins it at `prepare-reads`.

`detected_targets.txt` gives every target index that received a read, plus `NONE`, one `<tgidx>\t<reads>` line each, and is published for the record. Nothing downstream reads it: the arm fan-out and the gate both take their arms **and** their read counts from `prepare_target_distribution_mqc.json`, so the two can never disagree.

### Arm gate

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/arm_gate.tsv`: one row per candidate arm, with columns `sample`, `arm`, `tgidx`, `reads`, `threshold`, `status`.

</details>

An arm carrying fewer reads than `--min_arm_reads` is recorded as `FAIL`, warned about, and **dropped — not failed**. It reaches no aligner, its sibling arms and every other sample are unaffected, and **the run still exits 0**.

Trimming re-runs the same check on what it left behind, so an arm's row carries its **post-trim** read count and, where trimming took it below the threshold, the status `FAIL_TRIM`. The post-trim verdict replaces the pre-trim row rather than adding a second one: two rows under one arm would collide on MultiQC's row key, and a stale `PASS` beside a post-trim failure would hide the sample from `--fail_on_no_arms`. Under `--skip_trimming` every row is the pre-trim verdict.

The file is written once both verdicts are known, which is after the last fastp task rather than at the gate itself. A run that dies in an aligner therefore leaves no `arm_gate.tsv` behind; `--stop_after gate` still writes one.

A sample whose every arm falls below the threshold drops out of the run entirely, and the run still succeeds. `--fail_on_no_arms` turns that one case into an error naming the sample.

The same table appears in the MultiQC report as the "Arm gate" section.

### scRNA arm

<details markdown="1">
<summary>Output files</summary>

- `fastp/<sample>.none/`: the fastp JSON, HTML and log for the arm.
- `fastqc/prepared/<sample>.none/`: FastQC on the trimmed cDNA read STARsolo aligns.
- `star/<sample>.none/`
  - `<sample>.none.Solo.out/`: the count matrices, one directory per feature — `Gene`, plus whatever `--solo_features` asked for.
  - `<sample>.none.Log.final.out` and the other STAR logs.

</details>

The cDNA pair is trimmed first, paired-end and trim-only: `--disable_quality_filtering --length_required 1`. STAR soft-clips what it cannot align, so this arm trims to stop adapter read-through from displacing the cDNA rather than to raise its quality — a read fastp discards is a cell STARsolo never counts. The length floor of 1 keeps a read that adapter trimming consumed entirely from reaching STAR as a zero-length record. No adapter FASTA is passed: the arm is left on fastp's own overlap analysis, which is what the measured comparison on this chemistry found sufficient.

Trimming drops whole records from the cDNA read, and STARsolo pairs its two input files positionally, record for record — so the read ids that survived are replayed onto carmack's synthesized barcode read before STAR sees it. Without that step every read after the first dropped one would be counted against the wrong cell, and the run would still succeed. The trimmed FASTQs and the resynced barcode read are intermediates and are not published.

No alignment file is written: the matrices are the product, so STARsolo runs with `--outSAMtype None`. The STAR index is an intermediate and is not published.

### scTIP arm

<details markdown="1">
<summary>Output files</summary>

- `fastp/<chemistry>.adapters.fasta`: the sequences the run trimmed against, both orientations.
- `fastp/<sample>.<tgidx>/`: the fastp JSON, HTML and log for that arm.
- `fastqc/prepared/<sample>.<tgidx>/`: FastQC on the pair bowtie2 aligns, after trimming.
- `bowtie2/<sample>.<tgidx>/<sample>.<tgidx>.bowtie2.log`: the alignment summary.
- `umitools/<sample>.<tgidx>/`
  - `<sample>.<tgidx>.bam` and `.bam.bai`: deduplicated per cell and UMI.
  - `<sample>.<tgidx>.log`: the `umi_tools dedup` run log.
- `lineardedup/<sample>.<tgidx>/`
  - `<sample>.<tgidx>.linear_dedup.bam` and `.bam.bai`: the arm's final BAM, linear-amplification duplicates collapsed.
  - `<sample>.<tgidx>.linear_dedup_stats.txt`, plus one `*_mqc.json` per MultiQC payload.
- `samtools/<sample>.<tgidx>/<sample>.<tgidx>.stats`: `samtools stats` on whichever BAM the arm ended on.

</details>

bowtie2 runs end to end, so adapter read-through costs the whole alignment rather than a soft clip: the arm is trimmed first, with `--trim_poly_g` and `--length_required 25`. Quality trimming is deliberately absent — it would shorten reads, moving the leftmost coordinate of a reverse-strand alignment, which is both the key `umi_tools dedup` groups on and the insertion site carmack's linear pass groups on. The trimmed FASTQs are intermediates and are not published.

The aligned BAM is not published — it is superseded by the sort and the retagging before the arm finishes. Read names carry carmack's barcode and UMI through bowtie2 intact; those fields are lifted into `CB` and `UB` tags before deduplication, so the published BAM has bare read names and `CB:Z:`/`UB:Z:` tags. The bowtie2 index is an intermediate and is not published.

The arm deduplicates twice. `umi_tools dedup --paired` keys on the UMI together with the coordinates of both mates, which leaves intact the copies linear (T7 IVT) amplification made of one template: they share R1's 5' end but terminate independently, so they carry different mate ends and different UMIs and read as distinct molecules, inflating per-cell signal at each Tn5 insertion site. carmack's `linear-dedup` pass then keys per cell on that shared start alone — R1's strand-aware fragment position — keeping the highest-scoring pair of each group, and sorts and indexes its own output, so `lineardedup/<sample>.<tgidx>/<sample>.<tgidx>.linear_dedup.bam` is the arm's final BAM. `--skip_linear_dedup` leaves the `umitools/` BAM as the arm's result instead; `samtools stats` reports on whichever the arm ended on.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. The report carries one FastQC row per raw read file and per arm, the arm-gate table, and the fastp, bowtie2, `umi_tools` and `samtools stats` logs, alongside the software versions used by the run.

carmack's own `*_mqc.json` payloads reach the report too, gathered under one **Carmack** section and ordered as the reads pass through the stages — barcode extraction, UMI extraction, target assignment, prepare-reads, then the scTIP arm's linear dedup — rather than alphabetically, which is what the `report_section_order` block in `assets/multiqc_config.yml` is for. Each stage also contributes its headline percentages to the General Statistics table.

Prepare-reads' own section is the **Prepare Reads Output Arm Distribution** bargraph: one bar per output arm, a category per scTIP target bucket plus `NONE` for the scRNA arm, so the categories partition every read the run saw. It is the same distribution the arm fan-out gates on, which makes it the fastest place to see why an arm was dropped.

Linear dedup adds two bargraphs: **Linear Dedup Breakdown**, one bar per arm split into pairs kept, pairs removed and the pairs skipped as ineligible, and **Linear Dedup: Duplicates Removed per Chromosome**. Its General Statistics columns are **% Duplication** and **% Missing AS**, both over eligible pairs. Neither section nor column is present under `--skip_linear_dedup`.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow, each stamped with the run's timestamp: `execution_report_*.html`, `execution_timeline_*.html`, `execution_trace_*.txt` and `pipeline_dag_*.html`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `jacquard_software_mqc_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - The arm-gate record: `arm_gate.tsv`.
  - Parameters used by the pipeline run: `params_*.json`.

</details>

[Nextflow](https://docs.seqera.io/platform-cloud/reports/overview) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
