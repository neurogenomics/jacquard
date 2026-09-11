process CARMACK_VERSION {
    label 'process_single'

    container 'ghcr.io/crick-pipelines-stp/carmack:local'

    output:
    tuple val("${task.process}"), val('carmack'), eval('carmack --version | sed -n "s/^carmack, version //p"'), emit: versions_carmack, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    carmack --version
    """
}
