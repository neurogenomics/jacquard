//
// Read preparation: QC the raw pair, then run carmack's R1 chain and rejoin the raw R2 for
// prepare-reads.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQC                  } from '../../../modules/nf-core/fastqc/main'
include { CARMACK_EXTRACTBARCODES } from '../../../modules/local/carmack/extractbarcodes/main'
include { CARMACK_EXTRACTUMIS     } from '../../../modules/local/carmack/extractumis/main'
include { CARMACK_ASSIGNTARGETS   } from '../../../modules/local/carmack/assigntargets/main'
include { CARMACK_PREPAREREADS    } from '../../../modules/local/carmack/preparereads/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CARMACK_READPREP {

    take:
    ch_reads  // channel: [ val(meta), [ path(fastq_1), path(fastq_2) ] ]
    chemistry // value:   name of the carmack chemistry preset

    main:

    // Every carmack module reports its version on the `versions` topic, so nothing is mixed in
    // here; the emit exists for callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    def ch_pair = ch_reads.map { meta, fastqs ->
        if (fastqs.size() != 2) {
            error("Sample '${meta.id}' carries ${fastqs.size()} FASTQ file(s); read preparation needs exactly one R1/R2 pair.")
        }
        [ meta, fastqs[0], fastqs[1] ]
    }

    // Fed from the validated pair rather than from `ch_reads`, so a malformed samplesheet aborts
    // the run before any FastQC task is submitted.
    FASTQC(ch_pair.map { meta, r1, r2 -> [ meta, [ r1, r2 ] ] })

    //
    // Only R1 carries the barcode, UMI and target index, so the chain below reads R1 alone.
    //
    CARMACK_EXTRACTBARCODES(ch_pair.map { meta, r1, _r2 -> [ meta, r1 ] }, chemistry)
    CARMACK_EXTRACTUMIS(CARMACK_EXTRACTBARCODES.out.reads, chemistry)
    CARMACK_ASSIGNTARGETS(CARMACK_EXTRACTUMIS.out.reads, chemistry)

    //
    // prepare-reads writes both arms, so it needs the original R2 the chain never touched.
    // failOnMismatch turns join's default silent drop into an abort: a sample whose R2 went
    // missing must stop the run rather than disappear from the results.
    //
    def ch_prepare = CARMACK_ASSIGNTARGETS.out.reads
        .join(ch_pair.map { meta, _r1, r2 -> [ meta, r2 ] }, failOnMismatch: true, failOnDuplicate: true)

    CARMACK_PREPAREREADS(ch_prepare, chemistry)

    def ch_multiqc_files = channel.empty()
        .mix(FASTQC.out.zip)
        .mix(CARMACK_EXTRACTBARCODES.out.multiqc)
        .mix(CARMACK_EXTRACTUMIS.out.multiqc)
        .mix(CARMACK_ASSIGNTARGETS.out.multiqc)
        .mix(CARMACK_PREPAREREADS.out.multiqc)
        .map { _meta, files -> files }
        .flatten()

    emit:
    scrna         = CARMACK_PREPAREREADS.out.scrna   // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    sctip         = CARMACK_PREPAREREADS.out.sctip   // channel: [ val(meta), [ path(fastq) ] ] — empty unless the chemistry whitelists target indices
    stats         = CARMACK_PREPAREREADS.out.stats   // channel: [ val(meta), path(prepare_stats.txt) ]
    targets       = CARMACK_PREPAREREADS.out.targets // channel: [ val(meta), path(detected_targets.txt) ]
    multiqc_files = ch_multiqc_files                 // channel: path(mqc_file)
    versions      = ch_versions                      // channel: [ path(versions.yml) ]
}
