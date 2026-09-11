process CARMACK_PREPAREREADS {
    tag "$meta.id"
    label 'process_medium'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    input:
    tuple val(meta), path(r1_tgidx), path(r2)
    val chemistry

    output:
    tuple val(meta), path("scrna/*.none.r1.fastq.gz"), path("scrna/*.none.r2.fastq.gz"), path("scrna/*.none.barcodes.fastq.gz"), emit: scrna
    tuple val(meta), path("sctip/*.fastq.gz")          , emit: sctip, optional: true
    tuple val(meta), path("*.prepare_stats.txt")       , emit: stats
    tuple val(meta), path("*.detected_targets.txt")    , emit: targets
    tuple val(meta), path("*_mqc.json", arity: '1..*') , emit: multiqc
    tuple val("${task.process}"), val('carmack'), eval('carmack --version | sed -n "s/^carmack, version //p"'), emit: versions_carmack, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # carmack writes both arms into a directory of its own, so sorting them apart there cannot
    # reach a staged input: the raw R2 is named like a per-target output often enough to matter.
    mkdir -p out scrna sctip

    carmack --hide-progress prepare-reads \\
        "$r1_tgidx" \\
        "$r2" \\
        --chemistry "$chemistry" \\
        --output_dir out \\
        --prefix "$prefix" \\
        --cpu_count $task.cpus \\
        $args

    shopt -s nullglob
    mv "out/${prefix}.none.r1.fastq.gz" "out/${prefix}.none.r2.fastq.gz" "out/${prefix}.none.barcodes.fastq.gz" scrna/
    for arm_fastq in out/*.fastq.gz; do
        mv "\$arm_fastq" sctip/
    done
    mv out/* .
    rmdir out
    """
}
