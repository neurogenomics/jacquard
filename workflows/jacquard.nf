/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { CARMACK_READPREP       } from '../subworkflows/local/carmack_readprep/main'
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

    // The fan-out writes the gate record and its report section, so a run that stops short of the
    // gate skips it outright: an empty input channel would still leave a header-only table behind,
    // claiming a gate the run never reached. The arms have no such sink and are cut on their input.
    if ('gate' in stages) {
        //
        // SUBWORKFLOW: Fan each sample out into its arms and gate each arm on its read count
        //
        ARM_FANOUT(
            CARMACK_READPREP.out.scrna,
            CARMACK_READPREP.out.sctip,
            CARMACK_READPREP.out.stats_json,
            params.min_arm_reads,
            params.fail_on_no_arms,
            outdir,
        )
        ch_versions = ch_versions.mix(ARM_FANOUT.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(ARM_FANOUT.out.multiqc_files)

        //
        // SUBWORKFLOW: QC and quantify every scRNA arm that cleared the gate
        //
        SCRNA_ARM(
            'arms' in stages ? ARM_FANOUT.out.scrna : channel.empty(),
            fasta,
            gtf,
            star_index,
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
        )
        ch_versions = ch_versions.mix(SCTIP_ARM.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(SCTIP_ARM.out.multiqc_files)
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
