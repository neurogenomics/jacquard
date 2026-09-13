//
// The scRNA arm: QC the reads prepare-reads wrote for it, then quantify them with STARsolo.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQC as FASTQC_PREPARED } from '../../../modules/nf-core/fastqc/main'
include { STAR_GENOMEGENERATE       } from '../../../modules/nf-core/star/genomegenerate/main'
include { STAR_STARSOLO             } from '../../../modules/nf-core/star/starsolo/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SCRNA_ARM {

    take:
    ch_arm     // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    fasta      //   value: genome FASTA, used to build an index when `star_index` is not given
    gtf        //   value: gene annotation GTF, used to build an index when `star_index` is not given
    star_index //   value: prebuilt STAR index, or null to build one from `fasta` and `gtf`

    main:

    // Both modules report their versions on the `versions` topic, so nothing is mixed in here; the
    // emit exists for callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    //
    // FastQC on the cDNA read STARsolo aligns rather than on the raw input pair, so the report
    // carries read quality per arm — one row per target index — instead of for the library as a
    // whole. `meta.id` is already `<sample>.<tgidx>`, so that row names itself.
    //
    FASTQC_PREPARED(ch_arm.map { meta, r1, _r2, _barcodes -> [ meta, r1 ] })

    //
    // The reference is derived from the arm channel rather than read straight off the parameters,
    // so a run whose scRNA arms were all dropped by the gate submits no STAR task at all instead of
    // building an index it has nothing to align. `first()` makes the result a value channel, so one
    // index serves every arm of every sample.
    //
    // Wanting a reference is checked on that same channel rather than in the workflow body, because
    // a body statement is evaluated when the subworkflow is instantiated: a run whose every scRNA
    // arm fell below `--min_arm_reads` would then abort for want of a reference no task was ever
    // going to read, which is the one outcome the gate exists to prevent.
    //
    def ch_reference = ch_arm.first().map { meta, _r1, _r2, _barcodes ->
        if (!star_index && !(fasta && gtf)) {
            error("Arm '${meta.id}' has no reference to map against: pass --star_index, or --fasta and --gtf to build one.")
        }
        meta
    }

    def ch_index = channel.empty()
    if (star_index) {
        ch_index = ch_reference.map { _meta -> [ [ id: 'star' ], file(star_index, checkIfExists: true) ] }
    }
    else {
        STAR_GENOMEGENERATE(
            ch_reference.map { _meta -> [ [ id: 'genome' ], file(fasta, checkIfExists: true) ] },
            ch_reference.map { _meta -> [ [ id: 'genome' ], file(gtf, checkIfExists: true) ] },
        )
        // Every input the build took was a value channel, so its output is one too and needs no
        // `first()` of its own to serve more than one arm.
        ch_index = STAR_GENOMEGENERATE.out.index
    }

    //
    // STARsolo's CB_UMI_Simple takes exactly one cDNA read and one barcode read, so of the arm's
    // three files it is handed `r1` — the cDNA insert prepare-reads trimmed R1 down to — and
    // `barcodes`, the synthesized corrected-barcode-plus-UMI record. `r2` is the other mate of the
    // same cDNA fragment and has no place in a run that maps a single read. The module renders
    // `--readFilesIn` as its second file then its first, so the pair is handed over barcodes-first
    // to reach STAR cDNA-first.
    //
    // carmack has already corrected every barcode against the chemistry's own whitelists, so
    // STARsolo is run whitelist-free: a second correction here could only disagree with the first
    // and split one physical cell in two. The module reads that off a placeholder path named
    // NO_FILE, which is what the absence of a whitelist is spelled as.
    //
    STAR_STARSOLO(
        ch_arm.map { meta, r1, _r2, barcodes -> [ meta, 'CB_UMI_Simple', [ barcodes, r1 ] ] },
        file("${projectDir}/assets/NO_FILE"),
        ch_index,
    )

    def ch_multiqc_files = channel.empty()
        .mix(FASTQC_PREPARED.out.zip)
        .mix(STAR_STARSOLO.out.log_final)
        .map { _meta, files -> files }
        .flatten()

    emit:
    counts        = STAR_STARSOLO.out.counts    // channel: [ val(meta), path(*.Solo.out) ]
    summary       = STAR_STARSOLO.out.summary   // channel: [ val(meta), path(Gene/Summary.csv) ]
    log_final     = STAR_STARSOLO.out.log_final // channel: [ val(meta), path(*Log.final.out) ]
    index         = ch_index                    // channel: [ val(meta), path(star) ]
    multiqc_files = ch_multiqc_files            // channel: path(mqc_file)
    versions      = ch_versions                 // channel: [ path(versions.yml) ]
}
