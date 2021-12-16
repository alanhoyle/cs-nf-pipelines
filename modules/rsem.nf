process RSEM_REF_PULL {
  publishDir "${params.outdir}/rsem/ref"

  output:
  tuple file("*.gtf"), file("*.fa")

  when:
  params.ref_pull=='true'

  script:
  """
  wget ftp://ftp.ensembl.org/pub/release-82/fasta/mus_musculus/dna/Mus_musculus.GRCm38.dna.toplevel.fa.gz
  wget ftp://ftp.ensembl.org/pub/release-82/gtf/mus_musculus/Mus_musculus.GRCm38.82.chr.gtf.gz
  gunzip Mus_musculus.GRCm38.dna.toplevel.fa.gz
  gunzip Mus_musculus.GRCm38.82.chr.gtf.gz
  """
}

process RSEM_REF_BUILD {
  publishDir "${params.outdir}/rsem/ref"
  container "dceoy/rsem"

  input:
  tuple file(gtf), file(fa)

  output:
  file("*")

  script:
        """
        rsem-prepare-reference \
        --gtf ${gtf} \
        --bowtie2 \
        ${fa} \
        ${params.species}

        """
}

process RSEM_EXPRESSION {
  publishDir "${params.outdir}/rsem/exp"
  container "dceoy/rsem"

  input:
  tuple val(sampleId), file(R1), file(R2)
  file(ref_files)

  output:
  file "*"

  script:
  """
  rsem-calculate-expression -p 8 --paired-end \
  --bowtie2 \
  --estimate-rspd \
  --append-names \
  --output-genome-bam \
  ${R1} ${R2} \
  ${params.species} \
  Toy_Ex
  """
}

process RSEM_SIMULATE_READS{
  publishDir "${params.outdir}/rsem/sim"
  container "dceoy/rsem"
  
  input:
  tuple file(estimated_model_file), file(estimated_isoform_results)

  output:
  file "*"

  script:
  """
  reference_name ${estimated_model_file} ${estimated_isoform_results} 0.2 50000000 simulated_reads
  """
}
