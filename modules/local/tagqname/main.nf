process TAGQNAME {
    tag "$meta.id"
    label 'process_low'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.bam"), emit: bam
    tuple val("${task.process}"), val('pysam'), eval("python3 -c 'import pysam; print(pysam.__version__)'"), emit: versions_pysam, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    tag_qname_to_bam.py \\
        --input "$bam" \\
        --output "${prefix}.bam" \\
        --threads $task.cpus \\
        $args
    """
}
