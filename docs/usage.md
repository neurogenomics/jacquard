# neurogenomics/jacquard: Usage

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

jacquard prepares scMultiome reads with [carmack](https://github.com/crick-pipelines-stp/carmack), then fans
each sample out into one **scRNA arm** and one **scTIP arm** per target index found in the library, gating
each arm on its read count before aligning it. See [output.md](output.md) for what each arm writes.

## Samplesheet input

A comma-separated file with three columns and a header row, one row per sample:

```bash
--input '[path to samplesheet file]'
```

```csv title="samplesheet.csv"
sample,fastq_1,fastq_2
CONTROL_REP1,AEG588A1_S1_L002_R1_001.fastq.gz,AEG588A1_S1_L002_R2_001.fastq.gz
CONTROL_REP2,AEG588A2_S2_L002_R1_001.fastq.gz,AEG588A2_S2_L002_R2_001.fastq.gz
```

| Column    | Description                                                                              |
| --------- | ---------------------------------------------------------------------------------------- |
| `sample`  | Sample name, unique across the samplesheet. Cannot contain spaces.                       |
| `fastq_1` | Full path to the reads 1 FastQ. Must be gzipped, with extension `.fastq.gz` or `.fq.gz`. |
| `fastq_2` | Full path to the reads 2 FastQ, with the same requirements.                              |

All three columns are **mandatory**. Single-end input is not supported: carmack reads the barcode, UMI and
target index off R1 and carries the raw R2 through to `prepare-reads`, so a row with an empty `fastq_2` is
rejected during schema validation, before any process is submitted.

The pipeline does **not** concatenate multiple runs of the same sample. A `sample` value repeated across
rows is rejected at validation, so merge re-sequenced runs of a library into one R1/R2 pair before you
build the samplesheet.

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Pipeline parameters

`nextflow run neurogenomics/jacquard --help_full` prints every parameter with its full help text. The
parameters specific to this pipeline are below.

### Read preparation

| Parameter        | Default                  | Description                                                                                                                                                                                         |
| ---------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--chemistry`    | `carmack_custom_seq_1_0` | carmack chemistry describing the barcode, UMI and target-index layout of R1. One of `carmack_custom_seq_1_0`, `carmack_custom_seq_1_0_primd`, `hydrop`; the list tracks the vendored carmack build. |
| `--carmack_fast` | `false`                  | Pass `--fast` to `carmack extract-barcodes`, dropping its local-alignment fallback. Faster, at the cost of the barcodes only that stage recovers.                                                   |

### Arm gate

| Parameter           | Default | Description                                                                                                                      |
| ------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `--min_arm_reads`   | `1000`  | Reads an arm must carry to be processed. An arm below the threshold is dropped, not failed — see [Arm gate](output.md#arm-gate). |
| `--fail_on_no_arms` | `false` | Fail the run when every arm of a sample falls below `--min_arm_reads`, instead of dropping that sample and continuing.           |

`--fail_on_no_arms` does not fail fast. A sample's verdict is only complete once its read preparation
has finished, and the check waits for every sample to reach that point, by which time arms that
cleared the gate earlier may already be aligning. Expect it to abort a run partway through rather
than before any alignment work starts; what it buys you is that the failure is reported rather than
left as a sample quietly missing from the results.

### Trimming

| Parameter         | Default | Description                                                                                      |
| ----------------- | ------- | ------------------------------------------------------------------------------------------------ |
| `--skip_trimming` | `false` | Align and quantify the reads `prepare-reads` wrote, untrimmed. Every downstream step still runs. |

Each arm that clears the gate is trimmed with fastp against an adapter FASTA built from the sequences
the selected `--chemistry` declares, in both orientations — read-through reaches R2 as the reverse
complement, and fastp does not reverse-complement a FASTA entry for you. No adapter sequence is ever
configured; a chemistry declaring none falls back to fastp's read-pair overlap detection.

Trimming can leave an arm below `--min_arm_reads`. Such an arm is dropped exactly as the gate drops
one, and its row in `arm_gate.tsv` is **replaced** with a `FAIL_TRIM` verdict carrying the post-trim
count — see [Arm gate](output.md#arm-gate).

### Deduplication

| Parameter             | Default | Description                                                                                         |
| --------------------- | ------- | --------------------------------------------------------------------------------------------------- |
| `--skip_linear_dedup` | `false` | Leave the scTIP arm's alignments as `umi_tools dedup` left them, with no second deduplication pass. |

The scTIP arm deduplicates twice. `umi_tools dedup --paired` keys on the UMI together with the
coordinates of both mates, which collapses PCR duplicates but not the copies linear (T7 IVT)
amplification made of one template: those share R1's 5' end and terminate independently, so they
carry different mate ends and different UMIs and read as distinct molecules, inflating per-cell
signal at each Tn5 insertion site. carmack's `linear-dedup` pass keys on that shared start alone —
per cell, R1's strand-aware fragment position — and keeps the highest-scoring pair of each group.

`--skip_linear_dedup` ends the arm on the `umi_tools` BAM instead, which `samtools stats` then
reports on; the two linear-dedup MultiQC sections are absent — see
[scTIP arm](output.md#sctip-arm).

### scRNA arm

| Parameter         | Default    | Description                                                                                                                                                                                                                                                                                                                                                     |
| ----------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--solo_features` | `GeneFull` | Features STARsolo counts UMIs against, space-separated — one or more of `Gene`, `GeneFull`, `GeneFull_ExonOverIntron`, `GeneFull_Ex50pAS`, `SJ`, `Velocyto`, one count matrix each. `GeneFull` counts intronic reads too, which are a large fraction of real signal in Tn5-derived multiome material. `Gene` is always counted alongside whatever is asked for. |

### References

| Parameter         | Description                                                                                                                                                                                     |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--fasta`         | Genome FASTA. The scRNA arm builds its STAR index from this and `--gtf`; the scTIP arm builds its bowtie2 index from this alone.                                                                |
| `--gtf`           | Gene annotation. Required alongside `--fasta` when `--star_index` is not given, since STARsolo can only assign a read to a gene against an annotation.                                          |
| `--star_index`    | Prebuilt STAR index directory; skips index building for the scRNA arm. It must carry the annotation you intend to count against, which STARsolo reads out of the index rather than off `--gtf`. |
| `--bowtie2_index` | Prebuilt bowtie2 index directory — the directory `bowtie2-build` wrote, holding the `*.bt2` files, not a path prefix. Skips index building for the scTIP arm.                                   |

A reference is only demanded by the arm that would use it, and only once that arm has cleared the gate: a
run whose scTIP arms were all dropped needs no bowtie2 index at all.

### Stage control

`--stop_after <stage>` runs the pipeline as far as one stage and then reports. Unset, the whole pipeline
runs. MultiQC assembles a report from whichever stages ran, so every stop point leaves one behind.

| Stage      | Stops after                                                                      |
| ---------- | -------------------------------------------------------------------------------- |
| `barcodes` | `carmack extract-barcodes`                                                       |
| `umis`     | `carmack extract-umis`                                                           |
| `targets`  | `carmack assign-targets`                                                         |
| `readprep` | `carmack prepare-reads`                                                          |
| `gate`     | the arm fan-out and its gate report — no aligner runs, so no reference is needed |

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run neurogenomics/jacquard --input ./samplesheet.csv --outdir ./results --fasta genome.fa --gtf genes.gtf -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/running/run-pipelines#configuring-pipelines), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run neurogenomics/jacquard -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: './samplesheet.csv'
outdir: './results/'
fasta: 'genome.fa'
gtf: 'genes.gtf'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull neurogenomics/jacquard
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [neurogenomics/jacquard releases page](https://github.com/neurogenomics/jacquard/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow `24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) and [customise process resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
