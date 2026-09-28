process CARMACK_LINEARDEDUP {
    tag "$meta.id"
    label 'process_low'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("*.linear_dedup.bam")        , emit: bam
    tuple val(meta), path("*.linear_dedup.bam.bai")    , emit: bai
    tuple val(meta), path("*.linear_dedup_stats.txt")  , emit: stats
    tuple val(meta), path("*_mqc.json", arity: '1..*') , emit: multiqc
    tuple val("${task.process}"), val('carmack'), eval('carmack --version | sed -n "s/^carmack, version //p"'), emit: versions_carmack, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # carmack needs --output_dir to exist; it gets one of its own, as in the sibling modules, so the
    # staged input is never in the directory carmack writes, sorts and indexes into.
    mkdir -p out

    carmack --hide-progress linear-dedup \\
        "$bam" \\
        "$bai" \\
        --output_dir out \\
        --prefix "$prefix" \\
        $args

    mv out/* .
    rmdir out
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.linear_dedup.bam"
    touch "${prefix}.linear_dedup.bam.bai"
    touch "${prefix}.linear_dedup_stats.txt"
    echo '{}' > "${prefix}.linear_dedup_general_stats_mqc.json"
    echo '{}' > "${prefix}.linear_dedup_breakdown_mqc.json"
    echo '{}' > "${prefix}.linear_dedup_chromosome_breakdown_mqc.json"
    """
}
