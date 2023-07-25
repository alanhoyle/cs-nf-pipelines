#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// import modules
include {JAX_TRIMMER} from "${projectDir}/modules/utility_modules/jax_trimmer"
include {READ_GROUPS as READ_GROUPS_HUMAN;
         READ_GROUPS as READ_GROUPS_MOUSE} from "${projectDir}/modules/utility_modules/read_groups"
include {FASTQC} from "${projectDir}/modules/fastqc/fastqc"
include {GET_READ_LENGTH} from "${projectDir}/modules/utility_modules/get_read_length"
include {CHECK_STRANDEDNESS} from "${projectDir}/modules/python/python_check_strandedness"
include {XENOME_CLASSIFY} from "${projectDir}/modules/xenome/xenome"
include {RSEM_ALIGNMENT_EXPRESSION as RSEM_ALIGNMENT_EXPRESSION_HUMAN;
         RSEM_ALIGNMENT_EXPRESSION as RSEM_ALIGNMENT_EXPRESSION_MOUSE} from "${projectDir}/modules/rsem/rsem_alignment_expression"
include {PICARD_ADDORREPLACEREADGROUPS as PICARD_ADDORREPLACEREADGROUPS_HUMAN;
         PICARD_ADDORREPLACEREADGROUPS as PICARD_ADDORREPLACEREADGROUPS_MOUSE} from "${projectDir}/modules/picard/picard_addorreplacereadgroups"
include {PICARD_REORDERSAM as PICARD_REORDERSAM_HUMAN;
         PICARD_REORDERSAM as PICARD_REORDERSAM_MOUSE} from "${projectDir}/modules/picard/picard_reordersam"
include {PICARD_SORTSAM as PICARD_SORTSAM_HUMAN;
         PICARD_SORTSAM as PICARD_SORTSAM_MOUSE} from "${projectDir}/modules/picard/picard_sortsam"
include {PICARD_COLLECTRNASEQMETRICS as PICARD_COLLECTRNASEQMETRICS_HUMAN;
         PICARD_COLLECTRNASEQMETRICS as PICARD_COLLECTRNASEQMETRICS_MOUSE} from "${projectDir}/modules/picard/picard_collectrnaseqmetrics"

include {MULTIQC} from "${projectDir}/modules/multiqc/multiqc"

workflow PDX_RNASEQ {

    take:
        read_ch

    main:
    // Step 1: Qual_Stat, Get read group information, Run Xenome
    JAX_TRIMMER(read_ch)
    
    GET_READ_LENGTH(read_ch)
    
    if (params.read_type == 'PE') {
      xenome_input = JAX_TRIMMER.out.trimmed_fastq
    } else {
      xenome_input = JAX_TRIMMER.out.trimmed_fastq
    }

    // QC is assess on all reads. Mouse/human is irrelevant here. 
    FASTQC(JAX_TRIMMER.out.trimmed_fastq)

    CHECK_STRANDEDNESS(JAX_TRIMMER.out.trimmed_fastq)

    // Xenome Classification
    XENOME_CLASSIFY(xenome_input)

    human_reads = XENOME_CLASSIFY.out.xenome_human_fastq
                  .join(CHECK_STRANDEDNESS.out.strand_setting)
                  .join(GET_READ_LENGTH.out.read_length)
                  .map{it -> tuple(it[0]+'_human', it[1], it[2], it[3])}

    mouse_reads = XENOME_CLASSIFY.out.xenome_mouse_fastq
                  .join(CHECK_STRANDEDNESS.out.strand_setting)
                  .join(GET_READ_LENGTH.out.read_length)
                  .map{it -> tuple(it[0]+'_mouse', it[1], it[2], it[3])}

    // Step 2: RSEM Human and Stats: 

    RSEM_ALIGNMENT_EXPRESSION_HUMAN(human_reads, params.rsem_ref_files_human, params.rsem_star_prefix_human, params.rsem_ref_prefix_human)
    
    // Picard Alignment Metrics
    READ_GROUPS_HUMAN(human_reads.map{it -> tuple(it[0], it[1])}, "picard")

    add_replace_groups_human = READ_GROUPS_HUMAN.out.read_groups.join(RSEM_ALIGNMENT_EXPRESSION_HUMAN.out.bam)
    PICARD_ADDORREPLACEREADGROUPS_HUMAN(add_replace_groups_human)

    PICARD_REORDERSAM_HUMAN(PICARD_ADDORREPLACEREADGROUPS_HUMAN.out.bam, params.picard_dict_human)

    // Picard Alignment Metrics
    PICARD_SORTSAM_HUMAN(PICARD_REORDERSAM_HUMAN.out.bam)

    human_qc_input = PICARD_SORTSAM_HUMAN.out.bam.join(human_reads)
                     .map{it -> [it[0], it[1], it[3]]}
                     
    PICARD_COLLECTRNASEQMETRICS_HUMAN(human_qc_input, params.ref_flat_human, params.ribo_intervals_human)

    // Step 3 RSEM Mouse and Stats:

    RSEM_ALIGNMENT_EXPRESSION_MOUSE(mouse_reads, params.rsem_ref_files_mouse, params.rsem_star_prefix_mouse, params.rsem_ref_prefix_mouse)
    
    // Step 4: Picard Alignment Metrics
    READ_GROUPS_MOUSE(mouse_reads.map{it -> tuple(it[0], it[1])}, "picard")

    add_replace_groups_mouse = READ_GROUPS_MOUSE.out.read_groups.join(RSEM_ALIGNMENT_EXPRESSION_MOUSE.out.bam)
    PICARD_ADDORREPLACEREADGROUPS_MOUSE(add_replace_groups_mouse)

    PICARD_REORDERSAM_MOUSE(PICARD_ADDORREPLACEREADGROUPS_MOUSE.out.bam, params.picard_dict_mouse)

    // Step 5: Picard Alignment Metrics
    PICARD_SORTSAM_MOUSE(PICARD_REORDERSAM_MOUSE.out.bam)

    mouse_qc_input = PICARD_SORTSAM_MOUSE.out.bam.join(mouse_reads)
                     .map{it -> [it[0], it[1], it[3]]}
 
    PICARD_COLLECTRNASEQMETRICS_MOUSE(mouse_qc_input, params.ref_flat_mouse, params.ribo_intervals_mouse)


    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(JAX_TRIMMER.out.quality_stats.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.quality_stats.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(XENOME_CLASSIFY.out.xenome_stats.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(RSEM_ALIGNMENT_EXPRESSION_HUMAN.out.rsem_cnt.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(PICARD_COLLECTRNASEQMETRICS_HUMAN.out.picard_metrics.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(RSEM_ALIGNMENT_EXPRESSION_MOUSE.out.rsem_cnt.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(PICARD_COLLECTRNASEQMETRICS_MOUSE.out.picard_metrics.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect()
    )

}