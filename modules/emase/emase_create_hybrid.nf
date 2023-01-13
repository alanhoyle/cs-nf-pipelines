process EMASE_CREATE_HYBRID {
    
    // give a group of fastas, and a haplotype list 
    // 1. generate a hybrid genome
    // 2. generate transcript list
    // 3. generate bowtie index. 

    cpus 1
    memory {60.GB * task.attempt}
    time {30.hour * task.attempt}
    errorStrategy 'retry' 
    maxRetries 1

    container 'quay.io/jaxcompsci/emase_gbrs_alntools:89bbb10'

    publishDir "${params.pubdir}/emase", pattern: "[*.fa, *.info, *.tsv]", mode:'copy'
    publishDir "${params.pubdir}/emase/bowtie", pattern: "[*.ebwt]", mode:'copy'

    output:
    path file("*.fa"), emit: transcript_fasta
    path file("*.info"), emit: transcript_info
    path file("*.ebwt"), emit: bowtie_index

    script:
    """
    create-hybrid -F ${params.genome_file_list} -s ${params.haplotype_list} -o ./ --create-bowtie-index
    """
}


