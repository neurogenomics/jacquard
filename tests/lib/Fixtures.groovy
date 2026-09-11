/**
 * Helpers for pipeline-level nf-tests.
 */
class Fixtures {

    /**
     * Rewrite a committed test samplesheet's relative FASTQ paths to absolute ones and return the
     * path of the rewritten copy.
     *
     * nf-schema resolves a samplesheet's file fields against launchDir. For `nextflow run .` from
     * the repo root that is the repo root, so the committed sheet's repo-relative paths resolve;
     * under nf-test launchDir is `.nf-test/tests/<hash>/` and they do not. Rewriting keeps the
     * committed sheet the single source of truth rather than maintaining a second, absolute copy.
     */
    static String absolutise(String baseDir, String outputDir, String name = 'samplesheet_test.csv') {
        def src = new File(baseDir, "tests/data/${name}")
        def dst = new File(outputDir, name)
        dst.parentFile.mkdirs()
        def rows = src.readLines().findAll { it.trim() }
        def out = [rows.head()]
        rows.tail().each { row ->
            out << row.split(',', -1).toList().withIndex().collect { field, i ->
                (i == 0 || !field) ? field : new File(baseDir, field).absolutePath
            }.join(',')
        }
        dst.text = out.join('\n') + '\n'
        return dst.absolutePath
    }
}
