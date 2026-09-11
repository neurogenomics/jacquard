process CARMACK_ASSIGNTARGETS {
    tag "$meta.id"
    label 'process_medium'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(r1_umi)
    val chemistry

    output:
    tuple val(meta), path("*.r1_tgidx.fastq.gz")       , emit: reads
    tuple val(meta), path("*.tgidx_stats.txt")         , emit: stats
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

    carmack --hide-progress assign-targets \\
        "$r1_umi" \\
        --chemistry "$chemistry" \\
        --output_dir out \\
        --prefix "$prefix" \\
        --cpu_count $task.cpus \\
        $args

    mv out/* .
    rmdir out
    """
}
