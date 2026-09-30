//
// Fan a prepared sample out into one unit of work per arm, and gate each arm on the read count
// prepare-reads recorded for it.
//
// The verdict is emitted rather than written: trimming re-gates each surviving arm, so the run
// record and its report section are written once, by the caller, from both verdicts together.
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Rewrite a sample's meta into an arm's meta, keeping the sample name.
//
// carmack reports the scRNA arm as the target-index token `NONE` but names its files `none`. This
// is the only place in the pipeline that case fold happens; everything downstream reads `meta.id`,
// `meta.arm` or `meta.tgidx` rather than spelling either form again. Rewriting `meta.id` — instead
// of adding a field — is what lets downstream modules name their files and their MultiQC rows per
// arm with no `ext.prefix` configuration, so no module can silently collide two arms into one row.
//
def armMeta(Map meta, String tgidx) {
    def scrna = tgidx == 'NONE'
    meta + [
        id        : "${meta.id}.${scrna ? tgidx.toLowerCase() : tgidx}".toString(),
        sample    : meta.id,
        arm       : scrna ? 'scrna' : 'sctip',
        tgidx     : tgidx,
        single_end: false,
    ]
}

//
// Read the per-target read counts prepare-reads recorded for a sample.
//
def targetCounts(Map meta, Path stats_json) {
    def distribution = new groovy.json.JsonSlurper().parseText(stats_json.text)?.data
    // Keyed by the prefix prepare-reads ran under, which is `meta.id` unless `ext.prefix` overrides it.
    // Looked up with containsKey rather than an elvis, because an empty map is falsy in Groovy and
    // would fall through to the single-key fallback instead of reaching the error below.
    def counts = distribution?.containsKey(meta.id)
        ? distribution[meta.id]
        : (distribution?.size() == 1 ? distribution.values().first() : null)
    // An empty map is rejected too: a sample with no candidate arm at all would otherwise leave the
    // flatMap below with nothing to emit and disappear from the run silently.
    if (!counts) {
        error("Sample '${meta.id}': ${stats_json.name} carries no target distribution, so its arms cannot be determined.")
    }
    counts
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow ARM_FANOUT {

    take:
    ch_scrna        // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    ch_sctip        // channel: [ val(meta), [ path(fastq) ] ]
    ch_stats_json   // channel: [ val(meta), path(prepare_target_distribution_mqc.json) ]
    min_arm_reads   //   value: reads an arm must carry to proceed

    main:

    // Every gate decision is taken in a channel operator, so nothing is mixed in here; the emit
    // exists for callers that collect version files from their subworkflows.
    def ch_versions = channel.empty()

    //
    // One candidate arm per token in prepare-reads' own target distribution: every target index that
    // received a read, plus the scRNA arm, which that map always carries and whose count is 0 when
    // every read matched a target. Detection and the counts the gate needs come out of that one map,
    // so the two can never disagree, and the output directory is never globbed — it holds a bucket
    // file for every whitelisted target index whether or not a read landed in it, so globbing would
    // invent arms the distribution rightly leaves out. `min_arm_reads` is at least 1, so the one
    // zero-count candidate that can arise here can never proceed.
    //
    def ch_candidates = ch_stats_json.flatMap { meta, stats_json ->
        def counts = targetCounts(meta, stats_json)
        // A detected set of {NONE} alone is a pure scRNA library, not an error. The scRNA arm has to
        // carry reads of its own for that to be the diagnosis: a sample where every arm is empty is a
        // failed library, and the caller's per-sample rollup is the message it should get.
        if ((counts['NONE'] ?: 0) > 0 && counts.every { tgidx, reads -> tgidx == 'NONE' || reads == 0 }) {
            log.warn("Sample '${meta.id}': prepare-reads assigned no read to a target index, so this is a pure scRNA run.")
        }
        counts.collect { tgidx, reads -> [ armMeta(meta, tgidx), reads as long ] }
    }

    //
    // The verdict, taken once: both branches below and the gate record the caller writes read it.
    //
    def ch_verdict = ch_candidates.map { meta, reads ->
        def status = reads >= min_arm_reads ? 'PASS' : 'FAIL'
        if (status == 'FAIL') {
            log.warn("Arm '${meta.id}' carries ${reads} read(s), below --min_arm_reads ${min_arm_reads}; it is dropped and the run continues.")
        }
        [ meta, reads, status ]
    }

    def ch_gated = ch_verdict.branch { _meta, _reads, status ->
        pass: status == 'PASS'
        fail: true
    }

    //
    // Each arm's files are joined onto its verdict, so a dropped arm is simply a key with no
    // partner: it reaches no process, and neither the sample's other arms nor any other sample
    // notice. A gate FAIL can therefore never fail a task, which is what keeps one bad library from
    // discarding the completed work of a large run.
    //
    // `remainder: true` is what keeps the two unmatched directions apart. Files with no verdict are
    // the gate doing its job and are dropped here. A PASS verdict with no files is the opposite —
    // carmack accounted for an arm and then wrote nothing this side could name, which a renamed
    // bucket would cause — so it aborts rather than silently emptying the arm while `arm_gate.tsv`
    // goes on saying PASS. `failOnMismatch` cannot express that, since it would fire on the gate's
    // own drops too.
    //
    def ch_scrna_arm = ch_gated.pass
        .filter { meta, _reads, _status -> meta.arm == 'scrna' }
        .map { meta, _reads, _status -> [ meta.sample, meta ] }
        .join(ch_scrna.map { meta, r1, r2, barcodes -> [ meta.id, [ r1, r2, barcodes ] ] }, failOnDuplicate: true, remainder: true)
        .filter { _sample, meta, _files -> meta != null }
        .map { _sample, meta, files ->
            if (!files) {
                error("Arm '${meta.id}' cleared the gate, but prepare-reads left no scRNA read files for sample '${meta.sample}'.")
            }
            [ meta, files[0], files[1], files[2] ]
        }

    // prepare-reads names each bucket `<prefix>.<TGIDX>.r{1,2}.fastq.gz`; the target index is read
    // back off the file name, after the read-type suffix, so a prefix containing dots still parses.
    def ch_sctip_pairs = ch_sctip.flatMap { meta, fastqs ->
        [ fastqs ].flatten()
            .findAll { fastq -> fastq.name ==~ /.*\.r[12]\.fastq\.gz$/ }
            .groupBy { fastq -> fastq.name.replaceAll(/\.[^.]+\.fastq\.gz$/, '').tokenize('.').last() }
            .collect { tgidx, pair -> [ [ meta.id, tgidx ], pair.sort { fastq -> fastq.name } ] }
    }

    def ch_sctip_arm = ch_gated.pass
        .filter { meta, _reads, _status -> meta.arm == 'sctip' }
        .map { meta, _reads, _status -> [ [ meta.sample, meta.tgidx ], meta ] }
        .join(ch_sctip_pairs, failOnDuplicate: true, remainder: true)
        .filter { _key, meta, _fastqs -> meta != null }
        .map { _key, meta, fastqs ->
            if (!fastqs) {
                error("Arm '${meta.id}' cleared the gate, but prepare-reads left no read pair named for target index '${meta.tgidx}' of sample '${meta.sample}'.")
            }
            [ meta, fastqs ]
        }

    emit:
    scrna    = ch_scrna_arm // channel: [ val(meta), path(r1), path(r2), path(barcodes) ]
    sctip    = ch_sctip_arm // channel: [ val(meta), [ path(r1), path(r2) ] ]
    gate     = ch_verdict   // channel: [ val(meta), val(reads), val(status) ]
    versions = ch_versions  // channel: [ path(versions.yml) ]
}
