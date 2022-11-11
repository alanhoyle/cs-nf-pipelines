process CHAIN_EXTRACT_BADREADS {
  tag "$sampleID"

  cpus 2
  memory 4.GB
  time = '04:00:00'

  publishDir "${params.pubdir}/${ params.organize_by=='sample' ? sampleID+'/stats' : 'gatk' }", pattern: "*.log", mode: 'copy' 
  container 'broadinstitute/gatk:4.2.4.1'

  errorStrategy { [0,3,4].contains(task.exitStatus) ? 'ignore' : 'terminate' } 

  input:
  tuple val(sampleID), file(bam_sort_mm10)

  output:
  tuple val(sampleID), file("BAD_READS"), emit: bad_reads
  tuple val(sampleID), file("*ValidateSamFile.log"), emit: validate_log
  
  when: params.chain != null

  script:
  """
  gatk ValidateSamFile \
  -I ${bam_sort_mm10[0]} \
  -MODE VERBOSE -MO 10000000 \
  -O BAD_READS \
  --IGNORE MISSING_READ_GROUP \
  --IGNORE RECORD_MISSING_READ_GROUP \
  --IGNORE MISSING_TAG_NM \
  --IGNORE QUALITY_NOT_STORED \
  > ${sampleID}_ValidateSamFile.log 2>&1 || true
  """
}
