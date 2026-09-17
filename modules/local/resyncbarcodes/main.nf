process RESYNCBARCODES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
?         'https://depot.galaxyproject.org/singularity/python:3.12'
:         'biocontainers/python:3.12' }"

    input:
    tuple val(meta), path(reads), path(barcodes)

    output:
    tuple val(meta), path("*.resynced.barcodes.fastq.gz"), emit: barcodes
    tuple val("${task.process}"), val('python'), eval('python3 --version | sed "s/^Python //"'), emit: versions_python, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    resync_barcodes.py \\
        --reads "$reads" \\
        --barcodes "$barcodes" \\
        --output "${prefix}.resynced.barcodes.fastq.gz" \\
        $args
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo '' | gzip > "${prefix}.resynced.barcodes.fastq.gz"
    """
}
