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
star/<sample>.none/                  scRNA arm — Solo.out lives here
bowtie2/<sample>.<tgidx>/            scTIP arm — alignment log
umitools/<sample>.<tgidx>/           scTIP arm — deduplicated BAM
samtools/<sample>.<tgidx>/           scTIP arm — stats on that BAM
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
  - `*.detected_targets.txt`, `*.prepare_stats.txt`, `*.prepare_stats_mqc.json`.

</details>

Only R1 goes through the chain — it carries the barcode, UMI and target index — and the raw R2 rejoins it at `prepare-reads`.

`detected_targets.txt` lists every target index that received a read, plus `NONE`, and is published for the record. Nothing downstream reads it: the arm fan-out and the gate both take their arms **and** their read counts from `prepare_stats_mqc.json`, so the two can never disagree.

### Arm gate

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/arm_gate.tsv`: one row per candidate arm, with columns `sample`, `arm`, `tgidx`, `reads`, `threshold`, `status`.

</details>

An arm carrying fewer reads than `--min_arm_reads` is recorded as `FAIL`, warned about, and **dropped — not failed**. It reaches no aligner, its sibling arms and every other sample are unaffected, and **the run still exits 0**.

A sample whose every arm falls below the threshold drops out of the run entirely, and the run still succeeds. `--fail_on_no_arms` turns that one case into an error naming the sample.

The same table appears in the MultiQC report as the "Arm gate" section.

### scRNA arm

<details markdown="1">
<summary>Output files</summary>

- `fastqc/prepared/<sample>.none/`: FastQC on the cDNA read STARsolo aligns.
- `star/<sample>.none/`
  - `<sample>.none.Solo.out/`: the count matrices, one directory per feature — `Gene`, plus whatever `--solo_features` asked for.
  - `<sample>.none.Log.final.out` and the other STAR logs.

</details>

No alignment file is written: the matrices are the product, so STARsolo runs with `--outSAMtype None`. The STAR index is an intermediate and is not published.

### scTIP arm

<details markdown="1">
<summary>Output files</summary>

- `fastqc/prepared/<sample>.<tgidx>/`: FastQC on the pair bowtie2 aligns.
- `bowtie2/<sample>.<tgidx>/<sample>.<tgidx>.bowtie2.log`: the alignment summary.
- `umitools/<sample>.<tgidx>/`
  - `<sample>.<tgidx>.bam` and `.bam.bai`: deduplicated per cell.
  - `<sample>.<tgidx>.log`: the `umi_tools dedup` run log.
- `samtools/<sample>.<tgidx>/<sample>.<tgidx>.stats`: `samtools stats` on the deduplicated BAM.

</details>

The aligned BAM is not published — it is superseded by the sort and the retagging before the arm finishes. Read names carry carmack's barcode and UMI through bowtie2 intact; those fields are lifted into `CB` and `UB` tags before deduplication, so the published BAM has bare read names and `CB:Z:`/`UB:Z:` tags. The bowtie2 index is an intermediate and is not published.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. The report carries one FastQC row per raw read file and per arm, the arm-gate table, and the bowtie2, `umi_tools` and `samtools stats` logs, alongside the software versions used by the run.

> [!NOTE]
> carmack's own `*_mqc.json` files are published under `carmack/` but do not yet reach the report — MultiQC drops them silently. Tracked upstream as [carmack#95](https://github.com/crick-pipelines-stp/carmack/issues/95).

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
