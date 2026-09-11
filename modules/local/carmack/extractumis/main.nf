process CARMACK_EXTRACTUMIS {
    tag "$meta.id"
    label 'process_single'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(r1_annotated)
    val chemistry

    output:
    tuple val(meta), path("*.r1_umi.fastq.gz")         , emit: reads
    tuple val(meta), path("*.umi_stats.txt")           , emit: stats
    tuple val(meta), path("*_mqc.json", arity: '1..*') , emit: multiqc
    tuple val("${task.process}"), val('carmack'), eval('carmack --version | sed -n "s/^carmack, version //p"'), emit: versions_carmack, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # carmack writes into its own directory, mirroring PREPAREREADS where that separation is
    # what keeps a staged input out of the per-arm sort.
    mkdir -p out

    carmack --hide-progress extract-umis \\
        "$r1_annotated" \\
        --chemistry "$chemistry" \\
        --output_dir out \\
        --prefix "$prefix" \\
        $args

    mv out/* .
    rmdir out
    """
}
