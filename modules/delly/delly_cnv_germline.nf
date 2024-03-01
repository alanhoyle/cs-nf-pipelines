process DELLY_CNV_GERMLINE {
    tag "$sampleID"
    
    cpus = 1
    memory 80.GB
    time '12:00:00'
    errorStrategy {(task.exitStatus == 140) ? {log.info "\n\nError code: ${task.exitStatus} for task: ${task.name}. Likely caused by the task wall clock: ${task.time} or memory: ${task.mem} being exceeded.\nAttempting orderly shutdown.\nSee .command.log in: ${task.workDir} for more info.\n\n"; return 'finish'}.call() : 'finish'}
    
    container 'quay.io/biocontainers/delly:1.1.6--h6b1aa3f_2'
    
    input:
    tuple val(sampleID), path(bam), path(bai)
    tuple path(fasta), path(fai)

    output:
    tuple val(sampleID), path("${sampleID}_Delly.bcf"), emit: delly_bcf
    tuple val(sampleID), path("${sampleID}_Delly.bcf.csi"), emit: delly_csi
    tuple val(sampleID), path("${sampleID}_Delly.cov.gz"), emit: delly_cov


    script:
    """
    delly cnv -u -z ${params.cnv_min_size} -i ${params.cnv_window} -o ${sampleID}_Delly.bcf -c ${sampleID}_Delly.cov.gz -g ${fasta} -m ${params.delly_mappability} ${bam} 
    """
}
