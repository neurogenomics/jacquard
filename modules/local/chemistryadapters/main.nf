process CHEMISTRYADAPTERS {
    tag "$chemistry"
    label 'process_single'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    val chemistry

    output:
    path "*.adapters.fasta", emit: fasta
    tuple val("${task.process}"), val('carmack'), eval('carmack --version | sed -n "s/^carmack, version //p"'), emit: versions_carmack, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${chemistry}"
    """
    chemistry_adapter_fasta.py \\
        --chemistry "$chemistry" \\
        --output "${prefix}.adapters.fasta" \\
        $args
    """

    stub:
    def prefix = task.ext.prefix ?: "${chemistry}"
    """
    touch "${prefix}.adapters.fasta"
    """
}
