process GBRS_COMPRESS {
    tag "$sampleID"

    cpus 1
    memory { suffix == 'merged' ? 6.GB * task.attempt : 40.GB * task.attempt}
    time 10.hour
    errorStrategy 'finish' 

    container 'quay.io/mikewlloyd/gbrs_test:latest'

    publishDir "${params.pubdir}/${ params.organize_by=='sample' ? sampleID + '/gbrs' : 'gbrs' }", pattern: "*.h5", mode: 'copy', enabled: "${ suffix == 'merged' || params.read_type == 'SE' ? true : false }"

    input:
    tuple val(sampleID), path(bam)
    val(suffix)

    output:
    tuple val(sampleID), file("*.compressed.emase.h5"), emit: compressed_emase_h5

    script:
    bam_list = bam.collect { "$it" }.join(',')

    output_name = suffix == 'merged' ? "${sampleID}.merged.compressed.emase.h5" : "${bam[0].baseName}.compressed.emase.h5"

    """
    gbrs compress -i ${bam_list} -o ${output_name}
    """

    stub:
    """
    touch ${output_name}
    """
}

/*
usage: gbrs compress [-h] -i EMASEFILES -o OUTFILE [-c COMPLIB]

optional arguments:
  -h, --help            show this help message and exit
  -i EMASEFILES, --emase-files EMASEFILES
  -o OUTFILE
  -c COMPLIB
*/