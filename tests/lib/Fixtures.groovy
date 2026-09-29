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
     *
     * The copy is written beside the output directory rather than inside it. It is an input to the
     * run, and anything under `params.outdir` is swept up by `getAllFilesFromDir` as though the
     * pipeline had produced it: the copy would appear in the output listing, and its absolute paths
     * would make the content snapshot a function of where the repository happens to sit. A sibling
     * of the output directory is inside the test's own scratch area and outside everything the
     * snapshot reads.
     */
    static String absolutise(String baseDir, String outputDir, String name = 'samplesheet_test.csv') {
        def src = new File(baseDir, "tests/data/${name}")
        def dst = new File(new File(outputDir).parentFile, name)
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

    /**
     * Split the committed SK609 pair into two lanes under outputDir and return a samplesheet
     * listing both of them under one sample name.
     *
     * The cut is on a record boundary and the halves are written in order, so concatenating lane 1
     * and then lane 2 reproduces the committed file exactly. That is what lets a multi-lane run be
     * asserted against the single-lane fixture's own hashes and read counts, and what makes lanes
     * merged in the wrong order visible rather than merely differently ordered within a file.
     */
    static String lanes(String baseDir, String outputDir, int firstLaneRecords = 6000) {
        def lanes = [1, 2].collect { read ->
            def src = new File(baseDir, "tests/data/SK609_L5_R${read}.fastq.gz")
            def lines = new java.util.zip.GZIPInputStream(new FileInputStream(src)).withReader('UTF-8') { reader -> reader.readLines() }
            [lines[0..<firstLaneRecords * 4], lines[firstLaneRecords * 4..<lines.size()]].withIndex().collect { chunk, lane ->
                def dst = new File(outputDir, "SK609_L${lane + 1}_R${read}.fastq.gz")
                dst.parentFile.mkdirs()
                new java.util.zip.GZIPOutputStream(new FileOutputStream(dst)).withWriter('UTF-8') { writer ->
                    chunk.each { line -> writer << line << '\n' }
                }
                dst.absolutePath
            }
        }
        def sheet = new File(outputDir, 'samplesheet_lanes.csv')
        sheet.text = (['sample,fastq_1,fastq_2'] + [0, 1].collect { lane -> "SK609,${lanes[0][lane]},${lanes[1][lane]}" }).join('\n') + '\n'
        return sheet.absolutePath
    }

    /**
     * Return the path of a file a task wrote into the run's work directory, given the test's
     * `$workDir`.
     *
     * For an output no `publishDir` copies out, the work directory is the only place it can be
     * read. Downstream tasks stage it under the same name, so matches are canonicalised: every
     * staged copy is a symbolic link resolving to the one real file.
     */
    static String workFile(String workDir, String name) {
        def found = [] as Set
        new File(workDir).eachFileRecurse(groovy.io.FileType.FILES) { file ->
            if (file.name == name) {
                found << file.canonicalPath
            }
        }
        assert found.size() == 1: "expected one '${name}' under ${workDir}, found ${found}"
        return found.first()
    }

    /**
     * Return the messages a run passed to `log.warn`, given the test's `$workDir`.
     *
     * Nextflow 26 keeps `log.warn` off the console, so `workflow.stdout` never sees one — unlike
     * `error()`, which is reported there. The run's own log file, a sibling of the test work
     * directory, is the only place a warning is observable from a test.
     */
    static List<String> warnings(String workDir) {
        def marker = ' WARN  nextflow.Nextflow - '
        def log = new File(new File(workDir).parentFile, 'meta/nextflow.log')
        return log.readLines()
            .findAll { line -> line.contains(marker) }
            .collect { line -> line.substring(line.indexOf(marker) + marker.length()) }
    }
}
