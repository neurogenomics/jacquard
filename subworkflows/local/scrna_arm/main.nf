//
// The scRNA arm: trim the reads prepare-reads wrote for it, resync the barcode read to what
// survived, QC them, then quantify them with STARsolo.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTP                                 } from '../../../modules/nf-core/fastp/main'
include { ARM_TRIM_GATE                         } from '../arm_trim_gate/main'
include { RESYNCBARCODES                        } from '../../../modules/local/resyncbarcodes/main'
include { FASTQC as FASTQC_PREPARED             } from '../../../modules/nf-core/fastqc/main'
include { STAR_GENOMEGENERATE                   } from '../../../modules/nf-core/star/genomegenerate/main'
include { STAR_STARSOLO                         } from '../../../modules/nf-core/star/starsolo/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_SOLO } from '../../../modules/nf-core/samtools/index/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Drop the barcode geometry again, leaving the arm's own meta.
//
// The geometry travels on the meta because that is where the STARsolo module reads it from, and it
// is taken off every output so an arm is the same map wherever else it is joined or compared.
//
def armMeta(Map meta) {
    meta.subMap(meta.keySet() - [ 'cb_start', 'cb_len', 'umi_start', 'umi_len', 'barcode_len' ])
}

//
// Add STARsolo's barcode geometry to an arm's meta, from the layout prepare-reads wrote beside the
// barcode read.
//
// The sidecar gives 0-based offsets into that record and STAR counts its positions from 1, so each
// start is shifted by one here. Nothing about the chemistry is spelled out in this pipeline: a
// chemistry whose barcode or UMI changes length changes this file, and the flags follow it.
//
def soloGeometry(Map meta, Path layout_json) {
    def layout = new groovy.json.JsonSlurper().parseText(layout_json.text)
    def barcode = layout.cell_barcode
    def umi = layout.umi
    // CB_UMI_Simple can only read a cell barcode and a UMI at fixed offsets, so a record holding
    // anything else — a spacer between the two, or a chunk outside them — would be read as if the
    // bases it holds were barcode or UMI, and every count would be keyed on the wrong cell.
    if (barcode.start != 0 || umi.start != barcode.length || layout.length != barcode.length + umi.length) {
        error(
            "Arm '${meta.id}': ${layout_json.name} describes a ${layout.length} base barcode record " +
            "carrying a ${barcode.length} base cell barcode at offset ${barcode.start} and a " +
            "${umi.length} base UMI at offset ${umi.start}. STARsolo's CB_UMI_Simple can read only a " +
            "cell barcode at offset 0 followed immediately by a UMI, together filling the record."
        )
    }
    meta + [
        cb_start   : barcode.start + 1,
        cb_len     : barcode.length,
        umi_start  : umi.start + 1,
        umi_len    : umi.length,
        barcode_len: layout.length,
    ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SCRNA_ARM {

    take:
    ch_arm        // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    ch_layout     // channel: [ val(meta), path(barcodes.json) ], keyed by sample rather than by arm
    fasta         //   value: genome FASTA, used to build an index when `star_index` is not given
    gtf           //   value: gene annotation GTF, used to build an index when `star_index` is not given
    star_index    //   value: prebuilt STAR index, or null to build one from `fasta` and `gtf`
    skip_trimming //   value: run the arm on the reads prepare-reads wrote, untrimmed
    min_arm_reads //   value: read pairs an arm must still carry after trimming to proceed

    main:

    // Every module here reports its versions on the `versions` topic, so nothing is mixed in; the
    // emit exists for callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    //
    // Wanting a reference is checked here, on every arm that reached this subworkflow, rather than
    // in the workflow body: a body statement is evaluated when the subworkflow is instantiated, so
    // a run whose every scRNA arm fell below `--min_arm_reads` would abort for want of a reference
    // no task was ever going to read, which is the one outcome the gate exists to prevent. It is
    // deliberately the pre-trim channel, so a misconfigured run fails before it pays for trimming.
    //
    def ch_checked = ch_arm.map { meta, r1, r2, barcodes ->
        if (!star_index && !(fasta && gtf)) {
            error("Arm '${meta.id}' has no reference to map against: pass --star_index, or --fasta and --gtf to build one.")
        }
        [ meta, r1, r2, barcodes ]
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
        // The cDNA pair is trimmed paired-end so fastp can use the overlap of the two mates, which
        // is this arm's whole adapter analysis: it is given no adapter FASTA. The barcode read is
        // held back rather than passed as a third file — it is not a mate of the pair, it carries no
        // adapter, and fastp would judge it on the cDNA's own criteria.
        FASTP(ch_checked.map { meta, r1, r2, _barcodes -> [ meta, [ r1, r2 ], [] ] }, false, false, false)

        // The barcode read rejoins the trimmed pair unaltered, so the gate below and RESYNCBARCODES
        // after it both see the arm in the shape the rest of the subworkflow reads.
        def ch_trimmed = FASTP.out.reads
            .join(ch_checked.map { meta, _r1, _r2, barcodes -> [ meta, barcodes ] }, failOnDuplicate: true, failOnMismatch: true)
            .map { meta, reads, barcodes -> [ meta, reads[0], reads[1], barcodes ] }

        // Applied once, on the one channel every consumer below reads. Filtering only STARsolo's
        // input would leave a dropped arm publishing a FastQC report into the report as though it
        // had been processed.
        ARM_TRIM_GATE(ch_trimmed, FASTP.out.json, min_arm_reads)
        ch_gate = ARM_TRIM_GATE.out.gate
        ch_trim_json = FASTP.out.json

        //
        // STARsolo pairs its input files positionally, record for record, and fastp dropped whole
        // records out of the cDNA pair — both mates together, so `r1` and `r2` still agree.
        // Replaying the surviving read ids onto carmack's barcode read is what keeps it aligned with
        // them; without it every read after the first dropped one would be counted against the
        // wrong cell, and the run would still exit 0.
        //
        RESYNCBARCODES(ARM_TRIM_GATE.out.arms.map { meta, r1, _r2, barcodes -> [ meta, r1, barcodes ] })

        ch_reads = ARM_TRIM_GATE.out.arms
            .map { meta, r1, r2, _barcodes -> [ meta, r1, r2 ] }
            .join(RESYNCBARCODES.out.barcodes, failOnDuplicate: true, failOnMismatch: true)
    }

    //
    // FastQC on the cDNA pair STARsolo aligns rather than on the raw input pair, so the report
    // carries read quality per arm — one pair of rows per target index — instead of for the library
    // as a whole. `meta.id` is already `<sample>.<tgidx>`, so the two rows name themselves.
    //
    FASTQC_PREPARED(ch_reads.map { meta, r1, r2, _barcodes -> [ meta, [ r1, r2 ] ] })

    //
    // The reference is derived from the post-trim arm channel rather than read straight off the
    // parameters, so a run whose scRNA arms were all dropped — by the fan-out gate or by trimming —
    // submits no STAR task at all instead of building an index it has nothing to align. `first()`
    // makes the result a value channel, so one index serves every arm of every sample.
    //
    def ch_reference = ch_reads.first()

    def ch_index = channel.empty()
    if (star_index) {
        ch_index = ch_reference.map { _meta, _r1, _r2, _barcodes -> [ [ id: 'star' ], file(star_index, checkIfExists: true) ] }
    }
    else {
        STAR_GENOMEGENERATE(
            ch_reference.map { _meta, _r1, _r2, _barcodes -> [ [ id: 'genome' ], file(fasta, checkIfExists: true) ] },
            ch_reference.map { _meta, _r1, _r2, _barcodes -> [ [ id: 'genome' ], file(gtf, checkIfExists: true) ] },
        )
        // Every input the build took was a value channel, so its output is one too and needs no
        // `first()` of its own to serve more than one arm.
        ch_index = STAR_GENOMEGENERATE.out.index
    }

    //
    // The layout is written once per sample and read by that sample's one scRNA arm, so the two are
    // joined on the sample name. `remainder: true` keeps the two unmatched directions apart: a
    // layout with no arm is the gate having dropped the arm, and is simply discarded, while an arm
    // with no layout aborts — it is the one case where STARsolo would otherwise be left to read the
    // record on its 10x defaults, 16 barcode bases and 10 UMI bases, and count every read against a
    // truncated barcode while the run exited 0.
    //
    def ch_solo = ch_reads
        .map { meta, r1, r2, barcodes -> [ meta.sample, [ meta, r1, r2, barcodes ] ] }
        .join(ch_layout.map { meta, layout_json -> [ meta.id, layout_json ] }, failOnDuplicate: true, remainder: true)
        .filter { _sample, arm, _layout_json -> arm != null }
        .map { sample, arm, layout_json ->
            def (meta, r1, r2, barcodes) = arm
            if (!layout_json) {
                error("Arm '${meta.id}': prepare-reads wrote no barcode layout for sample '${sample}', so STARsolo cannot be told where the cell barcode and the UMI sit.")
            }
            [ soloGeometry(meta, layout_json), 'CB_UMI_Simple', [ r1, r2, barcodes ] ]
        }

    //
    // STARsolo maps the cDNA as a pair: `r1`, the insert prepare-reads cut R1 down to, and `r2`,
    // the other end of the same fragment, followed by `barcodes`, the resynced corrected-barcode-
    // plus-UMI record. With `--soloBarcodeMate 0` STAR takes a separate barcode read as the last file
    // listed, and the module passes three files through in the order given. Mapping `r1` alone
    // discards the longer mate: on a 6.46M-pair arm against GRCh38, counted unstranded, adding `r2`
    // raised uniquely mapped reads from 46.3% to 60.1%, the unique GeneFull fraction from 33.2% to
    // 42.0% and median UMI per cell from 206 to 258. Each fragment still counts once, under its one
    // barcode read.
    //
    // carmack has already corrected every barcode against the chemistry's own whitelists, so
    // STARsolo is run whitelist-free: a second correction here could only disagree with the first
    // and split one physical cell in two. The module reads that off a placeholder path named
    // NO_FILE, which is what the absence of a whitelist is spelled as.
    //
    STAR_STARSOLO(
        ch_solo,
        file("${projectDir}/assets/NO_FILE"),
        ch_index,
    )

    // STARsolo writes a BAM only when --solo_bam asks for one, so on a default run this indexes
    // nothing and `bam` stays empty.
    def ch_solo_bam = STAR_STARSOLO.out.bam.map { meta, bam -> [ armMeta(meta), bam ] }
    SAMTOOLS_INDEX_SOLO(ch_solo_bam)
    def ch_bam = ch_solo_bam.join(SAMTOOLS_INDEX_SOLO.out.index, failOnDuplicate: true, failOnMismatch: true)

    def ch_counts = STAR_STARSOLO.out.counts.map { meta, solo_out -> [ armMeta(meta), solo_out ] }
    def ch_summary = STAR_STARSOLO.out.summary.map { meta, summary -> [ armMeta(meta), summary ] }
    def ch_log_final = STAR_STARSOLO.out.log_final.map { meta, log_file -> [ armMeta(meta), log_file ] }

    // fastp's JSON goes to MultiQC for every arm it trimmed, including one the gate then dropped:
    // the report is the only place the reason for the drop is legible.
    def ch_multiqc_files = channel.empty()
        .mix(ch_trim_json)
        .mix(FASTQC_PREPARED.out.zip)
        .mix(ch_log_final)
        .map { _meta, files -> files }
        .flatten()

    emit:
    counts        = ch_counts                   // channel: [ val(meta), path(*.Solo.out) ]
    summary       = ch_summary                  // channel: [ val(meta), path(Gene/Summary.csv) ]
    log_final     = ch_log_final                // channel: [ val(meta), path(*Log.final.out) ]
    bam           = ch_bam                      // channel: [ val(meta), path(*.bam), path(*.bai) ]
    reads         = ch_reads                    // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    index         = ch_index                    // channel: [ val(meta), path(star) ]
    trim_json     = ch_trim_json                // channel: [ val(meta), path(*.fastp.json) ]
    gate          = ch_gate                     // channel: [ val(meta), val(reads), val(status) ]
    multiqc_files = ch_multiqc_files            // channel: path(mqc_file)
    versions      = ch_versions                 // channel: [ path(versions.yml) ]
}
