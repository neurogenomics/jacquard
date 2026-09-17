process CARMACK_EXTRACTBARCODES {
    tag "$meta.id"
    label 'process_high'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(fastq)
    val chemistry

    output:
    tuple val(meta), path("*.r1_annotated.fastq.gz")   , emit: reads
    tuple val(meta), path("*.bc_all.txt.gz")           , emit: bc_all
    tuple val(meta), path("*.bc_valid.txt.gz")         , emit: bc_valid
    tuple val(meta), path("*.bc_counts.csv")           , emit: counts
    tuple val(meta), path("*.bc_rank.png")             , emit: rank_plot
    tuple val(meta), path("*.bc_stats.txt")            , emit: stats
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

    carmack --hide-progress extract-barcodes \\
        "$fastq" \\
        --chemistry "$chemistry" \\
        --output_dir out \\
        --prefix "$prefix" \\
        --cpu_count $task.cpus \\
        $args

    mv out/* .
    rmdir out
    """
}
