//
// Re-run the arm gate on what trimming left behind, and drop the arms that no longer clear it.
//
// Both arms trim, and an arm that trimming empties is as useless to the aligner as one the fan-out
// gate dropped, so the check lives here once rather than once per arm.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Read the surviving read-pair count out of a fastp report.
//
// The gate's unit is read pairs — carmack's prepare-reads counts one per annotated R1 — so the
// count is read1's alone. `summary.after_filtering.total_reads` sums both mates and would make
// every comparison against `--min_arm_reads` exactly twice as lenient.
//
def trimmedReadPairs(Map meta, Path json) {
    def pairs = new groovy.json.JsonSlurper().parseText(json.text)?.read1_after_filtering?.total_reads
    if (pairs == null) {
        error("Arm '${meta.id}': ${json.name} carries no read1_after_filtering.total_reads, so the post-trim read count cannot be checked.")
    }
    pairs as long
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow ARM_TRIM_GATE {

    take:
    ch_arm        // channel: [ val(meta), ... ] — any arm tuple whose first element is the arm's meta
    ch_json       // channel: [ val(meta), path(*.fastp.json) ]
    min_arm_reads //   value: read pairs an arm must still carry to proceed

    main:

    // The verdict is taken in a channel operator, so nothing is mixed in here; the emit exists for
    // callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    def ch_verdict = ch_json.map { meta, json ->
        def reads = trimmedReadPairs(meta, json)
        def status = reads >= min_arm_reads ? 'PASS' : 'FAIL_TRIM'
        if (status != 'PASS') {
            log.warn("Arm '${meta.id}' carries ${reads} read pair(s) after trimming, below --min_arm_reads ${min_arm_reads}; it is dropped and the run continues.")
        }
        [ meta, reads, status ]
    }

    //
    // The two sides are joined on `meta.id` rather than on the meta itself, so an arm tuple of any
    // shape can be gated: the scRNA arm carries a barcode read the scTIP arm has no equivalent of.
    //
    // `remainder: true` is what turns each unmatched direction into a message. fastp's `reads`
    // output is `optional: true`, so a glob that stopped matching would empty the arm while the
    // report went on describing it — the arm would vanish and the run would still report success.
    //
    def ch_gated = ch_arm
        .map { arm -> [ arm[0].id, arm ] }
        .join(ch_verdict.map { meta, reads, status -> [ meta.id, reads, status ] }, failOnDuplicate: true, remainder: true)
        .map { id, arm, reads, status ->
            if (status == null) {
                error("Arm '${id}' was trimmed, but fastp left no report to check its read count against.")
            }
            if (arm == null) {
                error("Arm '${id}' reports ${reads} read pair(s) after trimming, but fastp left no trimmed read file behind.")
            }
            [ arm, status ]
        }
        .filter { _arm, status -> status == 'PASS' }
        .map { arm, _status -> arm }

    emit:
    arms     = ch_gated  // channel: [ val(meta), ... ] — the input tuples that still clear the gate
    gate     = ch_verdict // channel: [ val(meta), val(reads), val(status) ]
    versions = ch_versions // channel: [ path(versions.yml) ]
}
