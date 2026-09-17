/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { CARMACK_READPREP       } from '../subworkflows/local/carmack_readprep/main'
include { CHEMISTRYADAPTERS      } from '../modules/local/chemistryadapters/main'
include { ARM_FANOUT             } from '../subworkflows/local/arm_fanout/main'
include { SCRNA_ARM              } from '../subworkflows/local/scrna_arm/main'
include { SCTIP_ARM              } from '../subworkflows/local/sctip_arm/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_jacquard_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// The stages a run passes through, in the order it reaches them, truncated at `--stop_after`.
//
// This is the only place `--stop_after` is read for meaning: every boundary below asks whether its
// stage survived, so the flag cannot drift out of sync with itself the way a `when:` clause per
// module would. The stages are the pipeline's own boundaries, not carmack's command names, and
// `arms` terminates the list rather than being offered as a stop point, because stopping after the
// last stage is just running the pipeline.
//
def stagesUpTo(String stop_after) {
    def stages = [ 'barcodes', 'umis', 'targets', 'readprep', 'gate', 'arms' ]
    // A name this list does not carry would slice `stages[0..-1]` — the whole list — and run the
    // pipeline to the end while claiming to stop, so a stage the schema gained and this list did
    // not aborts here instead of hiding in the results.
    if (stop_after && !(stop_after in stages)) {
        error("--stop_after '${stop_after}' is not a stage this pipeline knows: ${stages.join(', ')}.")
    }
    stop_after ? stages[0..stages.indexOf(stop_after)] : stages
}

//
// The MultiQC custom-content header that turns the gate table into a report section.
//
def armGateMqcHeader() {
    [
        "# id: 'arm_gate'",
        "# section_name: 'Arm gate'",
        "# description: 'Reads assigned to each arm by carmack prepare-reads, and whether the arm met --min_arm_reads.'",
        "# plot_type: 'table'",
        "# pconfig:",
        "#     id: 'arm_gate_table'",
        "#     namespace: 'Arm gate'",
        [ 'Sample', 'Arm', 'Target index', 'Reads', 'Threshold', 'Status' ].join('\t'),
    ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow JACQUARD {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    chemistry      //   value: name of the carmack chemistry describing the read layout
    stop_after     //   value: stage the run stops after, or null to run the whole pipeline
    fasta          //   value: genome FASTA, used to build a STAR index when none is given
    gtf            //   value: gene annotation GTF, used to build a STAR index when none is given
    star_index     //   value: prebuilt STAR index, or null to build one
    bowtie2_index  //   value: prebuilt bowtie2 index, or null to build one
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    def stages = stagesUpTo(stop_after)

    //
    // SUBWORKFLOW: QC the raw reads and run carmack's read preparation chain
    //
    // The first four stop points are boundaries inside this subworkflow, so the surviving stages go
    // in with it rather than being enforced from out here.
    //
    CARMACK_READPREP(ch_samplesheet, chemistry, stages)
    ch_versions = ch_versions.mix(CARMACK_READPREP.out.versions)
    ch_multiqc_files = ch_multiqc_files.mix(CARMACK_READPREP.out.multiqc_files)

    // The gate record and its report section are written at the end of this block, so a run that
    // stops short of the gate skips it outright: an empty input channel would still leave a
    // header-only table behind, claiming a gate the run never reached. The arms have no such sink
    // and are cut on their input.
    if ('gate' in stages) {
        //
        // SUBWORKFLOW: Fan each sample out into its arms and gate each arm on its read count
        //
        ARM_FANOUT(
            CARMACK_READPREP.out.scrna,
            CARMACK_READPREP.out.sctip,
            CARMACK_READPREP.out.stats_json,
            params.min_arm_reads,
        )
        ch_versions = ch_versions.mix(ARM_FANOUT.out.versions)

        //
        // MODULE: Derive the adapters to trim against from the chemistry carmack ran under
        //
        // One FASTA per run, not per arm: the chemistry is a run-level parameter, so `first()`
        // makes it a value channel every arm can read. A chemistry declaring no sequence at all
        // still writes the file — an empty *channel* would starve fastp — and the empty file is
        // mapped to `[]` here so the module simply receives no `--adapter_fasta`.
        //
        def ch_adapter_fasta = channel.empty()
        if ('arms' in stages && !params.skip_trimming) {
            CHEMISTRYADAPTERS(chemistry)
            ch_adapter_fasta = CHEMISTRYADAPTERS.out.fasta.map { adapters -> adapters.size() > 0 ? adapters : [] }.first()
        }

        //
        // SUBWORKFLOW: QC and quantify every scRNA arm that cleared the gate
        //
        SCRNA_ARM(
            'arms' in stages ? ARM_FANOUT.out.scrna : channel.empty(),
            fasta,
            gtf,
            star_index,
            params.skip_trimming,
            params.min_arm_reads,
        )
        ch_versions = ch_versions.mix(SCRNA_ARM.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(SCRNA_ARM.out.multiqc_files)

        //
        // SUBWORKFLOW: Align and deduplicate every scTIP arm that cleared the gate
        //
        SCTIP_ARM(
            'arms' in stages ? ARM_FANOUT.out.sctip : channel.empty(),
            fasta,
            bowtie2_index,
            ch_adapter_fasta,
            params.skip_trimming,
            params.min_arm_reads,
        )
        ch_versions = ch_versions.mix(SCTIP_ARM.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(SCTIP_ARM.out.multiqc_files)

        //
        // The gate record and its report section, written once from both verdicts.
        //
        // Trimming re-gates every arm the fan-out passed, so the post-trim verdict **replaces** the
        // pre-trim row rather than being appended to it. Two rows under one `meta.id` would collide
        // on MultiQC's row key, and a stale PASS beside a post-trim `FAIL_TRIM` would leave the
        // rollup below finding one arm still passing — so a sample whose every arm trimming killed
        // would trigger neither `--fail_on_no_arms` nor the drop warning. `remainder: true` covers
        // the arms that have no post-trim verdict: the ones the fan-out already dropped, and every
        // arm of a run using `--skip_trimming` or stopping at `--stop_after gate`.
        //
        // Writing here rather than in ARM_FANOUT delays `arm_gate.tsv` until the last fastp task has
        // finished, so a run that dies in an aligner leaves no gate file behind.
        //
        def ch_verdicts = ARM_FANOUT.out.gate
            .map { verdict -> [ verdict[0].id, verdict ] }
            .join(
                SCRNA_ARM.out.gate.mix(SCTIP_ARM.out.gate).map { verdict -> [ verdict[0].id, verdict ] },
                failOnDuplicate: true,
                remainder: true,
            )
            .map { _id, gated, trimmed -> trimmed ?: gated }

        // The sample-level messages ride on the run record rather than on a channel of their own.
        // They need the same per-sample rollup the record's rows do, and putting them on a chain
        // that ends in a published file keeps --fail_on_no_arms out of reach of anyone tidying away
        // an emit nothing consumes. groupTuple cannot be given a `size:` — a sample's arm count is
        // only known once its prepare-reads has run — so it holds every sample until the last one is
        // ready: --fail_on_no_arms aborts a run whose other samples' arms are already aligning,
        // rather than failing fast.
        ch_verdicts
            .map { meta, reads, status -> [ meta.sample, [ arm: meta.arm, tgidx: meta.tgidx, reads: reads, status: status ] ] }
            .groupTuple()
            .map { sample, arms ->
                // Tested for the absence of a PASS rather than for `FAIL` alone, so an arm trimming
                // dropped counts against the sample under whichever token records the cause.
                if (arms.every { arm -> arm.status != 'PASS' }) {
                    def detail = arms.collect { arm -> "${arm.tgidx}=${arm.reads}" }.sort().join(', ')
                    if (params.fail_on_no_arms) {
                        error("Sample '${sample}' has no arm meeting --min_arm_reads ${params.min_arm_reads} (${detail}), and --fail_on_no_arms is set.")
                    }
                    log.warn("Sample '${sample}' has no arm meeting --min_arm_reads ${params.min_arm_reads} (${detail}); the sample is dropped and the run continues.")
                }
                arms.collect { arm -> [ sample, arm.arm, arm.tgidx, arm.reads, params.min_arm_reads, arm.status ].join('\t') }
            }
            .toList()
            .map { rows -> ([ [ 'sample', 'arm', 'tgidx', 'reads', 'threshold', 'status' ].join('\t') ] + rows.flatten().sort()).join('\n') + '\n' }
            .collectFile(name: 'arm_gate.tsv', storeDir: "${outdir}/pipeline_info")

        ch_multiqc_files = ch_multiqc_files.mix(
            ch_verdicts
                .map { meta, reads, status -> [ meta.id, meta.arm, meta.tgidx, reads, params.min_arm_reads, status ].join('\t') }
                .toList()
                .map { rows -> (armGateMqcHeader() + rows.sort()).join('\n') + '\n' }
                .collectFile(name: 'arm_gate_mqc.tsv')
        )
    }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'jacquard_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'jacquard'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
