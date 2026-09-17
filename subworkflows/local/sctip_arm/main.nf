//
// The scTIP arm: trim the reads prepare-reads wrote for a target index, QC them, align them with
// bowtie2, lift the barcode and UMI out of the read name into BAM tags, then deduplicate per cell.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTP                                   } from '../../../modules/nf-core/fastp/main'
include { ARM_TRIM_GATE                           } from '../arm_trim_gate/main'
include { FASTQC as FASTQC_PREPARED               } from '../../../modules/nf-core/fastqc/main'
include { BOWTIE2_BUILD                           } from '../../../modules/nf-core/bowtie2/build/main'
include { BOWTIE2_ALIGN                           } from '../../../modules/nf-core/bowtie2/align/main'
include { SAMTOOLS_SORT                           } from '../../../modules/nf-core/samtools/sort/main'
include { TAGQNAME                                } from '../../../modules/local/tagqname/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_TAGGED } from '../../../modules/nf-core/samtools/index/main'
include { UMITOOLS_DEDUP                          } from '../../../modules/nf-core/umitools/dedup/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_DEDUP  } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_STATS                          } from '../../../modules/nf-core/samtools/stats/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SCTIP_ARM {

    take:
    ch_arm           // channel: [ val(meta), [ path(r1), path(r2) ] ]
    fasta            //   value: genome FASTA, used to build an index when `bowtie2_index` is not given
    bowtie2_index    //   value: prebuilt bowtie2 index directory, or null to build one from `fasta`
    ch_adapter_fasta // channel: path(adapters.fasta) the chemistry declares, or `[]` when it declares none
    skip_trimming    //   value: run the arm on the reads prepare-reads wrote, untrimmed
    min_arm_reads    //   value: read pairs an arm must still carry after trimming to proceed

    main:

    // Every module here reports its versions on the `versions` topic, so nothing is mixed in; the
    // emit exists for callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    //
    // Wanting a reference is checked here, on every arm that reached this subworkflow, rather than
    // in the workflow body: a body statement is evaluated when the subworkflow is instantiated, so
    // a run whose every scTIP arm fell below `--min_arm_reads` would abort for want of a reference
    // no task was ever going to read, which is the one outcome the gate exists to prevent. It is
    // deliberately the pre-trim channel, so a misconfigured run fails before it pays for trimming.
    //
    def ch_checked = ch_arm.map { meta, reads ->
        if (!bowtie2_index && !fasta) {
            error("Arm '${meta.id}' has no reference to map against: pass --bowtie2_index, or --fasta to build one.")
        }
        [ meta, reads ]
    }

    //
    // Trimming is bypassed with a Groovy branch rather than `ext.when`: a process switched off by
    // `ext.when` emits nothing, so every consumer below would receive an empty channel and the arm
    // would produce no output at all, silently.
    //
    def ch_reads = ch_checked
    def ch_gate = channel.empty()
    def ch_trim_json = channel.empty()
    if (!skip_trimming) {
        // `combine` spreads a list-valued item across the tuple it builds, so an adapter channel
        // carrying a bare `[]` — the chemistry declaring no sequence at all — would contribute no
        // element and leave fastp's three-element input tuple two elements long. Wrapping it keeps
        // the shape whatever the chemistry declares.
        FASTP(ch_checked.combine(ch_adapter_fasta.map { adapters -> [ adapters ] }), false, false, false)

        // Applied once, on the one channel every consumer below reads. Filtering only the aligner's
        // input would leave a dropped arm publishing a FastQC report into the report as though it
        // had been processed.
        ARM_TRIM_GATE(FASTP.out.reads, FASTP.out.json, min_arm_reads)
        ch_reads = ARM_TRIM_GATE.out.arms
        ch_gate = ARM_TRIM_GATE.out.gate
        ch_trim_json = FASTP.out.json
    }

    //
    // FastQC on the pair bowtie2 aligns, so the report carries read quality per target index
    // rather than for the library as a whole. `meta.id` is already `<sample>.<tgidx>`, so the two
    // rows name themselves.
    //
    FASTQC_PREPARED(ch_reads)

    //
    // The reference is derived from the post-trim arm channel rather than read straight off the
    // parameters, so a run whose scTIP arms were all dropped — by the fan-out gate or by trimming —
    // submits no bowtie2 task at all instead of building an index it has nothing to align.
    // `first()` makes the result a value channel, so one index serves every arm of every sample.
    //
    def ch_reference = ch_reads.first()

    def ch_index = channel.empty()
    if (bowtie2_index) {
        ch_index = ch_reference.map { _meta, _reads -> [ [ id: 'bowtie2' ], file(bowtie2_index, checkIfExists: true) ] }
    }
    else {
        BOWTIE2_BUILD(ch_reference.map { _meta, _reads -> [ [ id: 'genome' ], file(fasta, checkIfExists: true) ] })
        ch_index = BOWTIE2_BUILD.out.index
    }

    // Every input either branch took was a value channel, so the index is one too and already
    // serves more than one arm. The `first()` says that outright instead of leaving a reader of
    // either branch to work it out from singleton inference.
    ch_index = ch_index.first()

    //
    // bowtie2 needs no flag to preserve carmack's barcode and UMI: a SAM QNAME is truncated at the
    // first whitespace, and `readid|CB=<barcode>|UR=<umi>` contains none, so the whole name reaches
    // the BAM. The reference FASTA is passed empty because only CRAM output would read it, and the
    // BAM is left unsorted here so the sort is a step that can be resumed on its own.
    //
    BOWTIE2_ALIGN(ch_reads, ch_index, [ [:], [] ], false, false)

    SAMTOOLS_SORT(BOWTIE2_ALIGN.out.bam, [ [:], [], [] ], '')

    //
    // umi_tools cannot read a UMI out of that composite QNAME safely — it validates no UMI
    // character, so the literal `UR=` and `CB=` strings would end up in every statistic — so the
    // fields are moved into real `CB`/`UB` tags first. That also leaves the BAM readable with a
    // plain `samtools view`.
    //
    // Safe ahead of the `--paired` dedup below because both mates of a pair carry the same
    // composite QNAME and so collapse to the same bare read id, and because rewriting names and
    // tags touches no coordinate — the BAM stays sorted, so it can simply be indexed here rather
    // than sorted again.
    //
    TAGQNAME(SAMTOOLS_SORT.out.bam)
    SAMTOOLS_INDEX_TAGGED(TAGQNAME.out.bam)

    // Output stats are left off: MultiQC reads the run log, and the per-UMI tables cost a
    // matplotlib render per arm that nothing downstream consumes.
    UMITOOLS_DEDUP(
        TAGQNAME.out.bam.join(SAMTOOLS_INDEX_TAGGED.out.index, failOnDuplicate: true, failOnMismatch: true),
        false,
    )
    SAMTOOLS_INDEX_DEDUP(UMITOOLS_DEDUP.out.bam)

    def ch_dedup = UMITOOLS_DEDUP.out.bam.join(SAMTOOLS_INDEX_DEDUP.out.index, failOnDuplicate: true, failOnMismatch: true)
    SAMTOOLS_STATS(ch_dedup, [ [:], [], [] ])

    // fastp's JSON goes to MultiQC for every arm it trimmed, including one the gate then dropped:
    // the report is the only place the reason for the drop is legible.
    def ch_multiqc_files = channel.empty()
        .mix(ch_trim_json)
        .mix(FASTQC_PREPARED.out.zip)
        .mix(BOWTIE2_ALIGN.out.log)
        .mix(UMITOOLS_DEDUP.out.log)
        .mix(SAMTOOLS_STATS.out.stats)
        .map { _meta, files -> files }
        .flatten()

    emit:
    bam           = ch_dedup                 // channel: [ val(meta), path(bam), path(bai) ]
    bam_aligned   = BOWTIE2_ALIGN.out.bam    // channel: [ val(meta), path(bam) ]
    reads         = ch_reads                 // channel: [ val(meta), [ path(r1), path(r2) ] ]
    log_dedup     = UMITOOLS_DEDUP.out.log   // channel: [ val(meta), path(*.log) ]
    log_align     = BOWTIE2_ALIGN.out.log    // channel: [ val(meta), path(*.bowtie2.log) ]
    stats         = SAMTOOLS_STATS.out.stats // channel: [ val(meta), path(*.stats) ]
    index         = ch_index                 // channel: [ val(meta), path(bowtie2) ]
    trim_json     = ch_trim_json             // channel: [ val(meta), path(*.fastp.json) ]
    gate          = ch_gate                  // channel: [ val(meta), val(reads), val(status) ]
    multiqc_files = ch_multiqc_files         // channel: path(mqc_file)
    versions      = ch_versions              // channel: [ path(versions.yml) ]
}
