#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// import modules
include {help} from "${projectDir}/bin/help/sv.nf"
include {param_log} from "${projectDir}/bin/log/sv.nf"
include {QUALITY_STATISTICS} from "${projectDir}/modules/utility_modules/quality_stats"
include {READ_GROUPS} from "${projectDir}/modules/utility_modules/read_groups"
include {BWA_MEM} from "${projectDir}/modules/bwa/bwa_mem"
include {PICARD_SORTSAM} from "${projectDir}/modules/picard/picard_sortsam"
include {SHORT_ALIGNMENT_MARKING} from "${projectDir}/modules/nygc-short-alignment-marking/short_alignment_marking"
include {PICARD_CLEANSAM} from "${projectDir}/modules/picard/picard_cleansam"
include {PICARD_FIX_MATE_INFORMATION} from "${projectDir}/modules/picard/picard_fix_mate_information"
include {PICARD_MARKDUPLICATES}	from "${projectDir}/modules/picard/picard_markduplicates"
include {GATK_BASERECALIBRATOR} from "${projectDir}/modules/gatk/gatk_baserecalibrator"
include {GATK_APPLYBQSR} from "${projectDir}/modules/gatk/gatk_applybqsr"
include {PICARD_COLLECTALIGNMENTSUMMARYMETRICS} from "${projectDir}/modules/picard/picard_collectalignmentsummarymetrics"
include {PICARD_COLLECTWGSMETRICS} from "${projectDir}/modules/picard/picard_collectwgsmetrics"
include {CONPAIR_TUMOR_PILEUP} from "${projectDir}/modules/conpair/conpair_tumor_pileup"
include {CONPAIR_NORMAL_PILEUP} from "${projectDir}/modules/conpair/conpair_normal_pileup"
include {CONPAIR} from "${projectDir}/modules/conpair/conpair"
include {GATKv3_5_HAPLOTYPECALLER} from "${projectDir}/modules/gatk/gatk3_haplotypecaller"
include {GATKv3_5_VARIANTRECALIBRATOR} from "${projectDir}/modules/gatk/gatk3_variantrecalibrator"

// help if needed
if (params.help){
    help()
    exit 0
}

// log paramiter info
param_log()

// main workflow
workflow SV {

    if (params.csv_input) {
        ch_input_sample = extract_csv(file(params.csv_input, checkIfExists: true))

        ch_input_sample.map{it -> [it[0], it[2]]}.set{read_ch}
        ch_input_sample.map{it -> [it[0], it[1]]}.set{meta_ch}
    }

    // Step 1: Qual_Stat
    QUALITY_STATISTICS(read_ch)

    // Step 2: Get Read Group Information
    READ_GROUPS(QUALITY_STATISTICS.out.trimmed_fastq, "gatk")

    // Step 3: BWA-MEM Alignment
    bwa_mem_mapping = QUALITY_STATISTICS.out.trimmed_fastq.join(READ_GROUPS.out.read_groups)
    BWA_MEM(bwa_mem_mapping)
    
    // Step 4: Sort mapped reads
    PICARD_SORTSAM(BWA_MEM.out.sam)

    // Step 5: Remove short mapping 'artifacts': https://github.com/nygenome/nygc-short-alignment-marking
    SHORT_ALIGNMENT_MARKING(PICARD_SORTSAM.out.bam)

    // Step 6: Clean BAM to set MAPQ = 0 when read is unmapped (issue introduced in step 5)
    PICARD_CLEANSAM(PICARD_SORTSAM.out.bam)

    // Step 7: Fix mate information (fix pair flags due to mapping adjustment in step 5)
    PICARD_FIX_MATE_INFORMATION(PICARD_CLEANSAM.out.cleaned_bam)

    // Step 8: Markduplicates
    PICARD_MARKDUPLICATES(PICARD_FIX_MATE_INFORMATION.out.fixed_mate_bam)

    // Step 9: Calculate BQSR
    GATK_BASERECALIBRATOR(PICARD_MARKDUPLICATES.out.dedup_bam)

    // Step 10: Apply BQSR
    apply_bqsr = PICARD_MARKDUPLICATES.out.dedup_bam.join(GATK_BASERECALIBRATOR.out.table)
    GATK_APPLYBQSR(apply_bqsr)

    // Step 12: Nextflow channel processing
    // https://github.com/nf-core/sarek/blob/master/workflows/sarek.nf#L854

    GATK_APPLYBQSR.out.bam.join(GATK_APPLYBQSR.out.bai).join(meta_ch).branch{
        normal: it[3].status == 0
        tumor:  it[3].status == 1
    }.set{chr_bam_status}
    // re-join the sampleID to metadata information. Split normal and tumor samples into 2 different paths. 
    // Process tumor and normal BAMs seperately for conpair. For calling, use mapped/joined data. 

    // Adjust channels to all normal, all tumor organized by patient IDs. 
    ch_bam_normal_to_cross = chr_bam_status.normal.map{ id, bam, bai, meta -> [meta.patient, meta, bam, bai] }
    ch_bam_tumor_to_cross = chr_bam_status.tumor.map{ id, bam, bai, meta -> [meta.patient, meta, bam, bai] }

    // Cross all normal and tumor by patient ID. 
    ch_cram_variant_calling_pair = ch_bam_normal_to_cross.cross(ch_bam_tumor_to_cross)
        .map { normal, tumor ->
            def meta = [:]
            meta.patient    = normal[0]
            meta.normal_id  = normal[1].sample
            meta.tumor_id   = tumor[1].sample
            meta.sex        = normal[1].sex
            meta.id         = "${meta.tumor_id}_vs_${meta.normal_id}".toString()

            [meta, normal[2], normal[3], tumor[2], tumor[3]]
        }
        // normal[0] is patient ID, normal[1] and tumor[1] are meta info, normal[2] is normal bam, normal[3] is bai. tumor[2] is bam, tumor[3] is bai.

    // Step 13: Conpair pileup for T/N
    CONPAIR_NORMAL_PILEUP(chr_bam_status.normal)
    CONPAIR_TUMOR_PILEUP(chr_bam_status.tumor)

    // output channel manipulation and cross/join
    conpair_normal_to_cross = CONPAIR_NORMAL_PILEUP.out.normal_pileup.map{ id, pileup, meta -> [meta.patient, meta, pileup] }
    conpair_tumor_to_cross = CONPAIR_TUMOR_PILEUP.out.tumor_pileup.map{ id, pileup, meta -> [meta.patient, meta, pileup] }

    conpair_input = conpair_normal_to_cross.cross(conpair_tumor_to_cross)
        .map { normal, tumor ->
            def meta = [:]
            meta.patient    = normal[0]
            meta.normal_id  = normal[1].sample
            meta.tumor_id   = tumor[1].sample
            meta.sex        = normal[1].sex
            meta.id         = "${meta.tumor_id}_vs_${meta.normal_id}".toString()

            [meta, normal[2], tumor[2]]
        }
        // normal[2] is normal pileup, tumor[2] is tumor pileup. 

    // Step 12: Conpair for T/N concordance: https://github.com/nygenome/conpair
    CONPAIR(conpair_input)
    // NOTE: NEED HIGH COVERAGE TO TEST. 

    // Step 13: Germline Calling
    GATKv3_5_HAPLOTYPECALLER(ch_bam_normal_to_cross)
    
    GATKv3_5_VARIANTRECALIBRATOR(GATKv3_5_HAPLOTYPECALLER.out.normal_germline_gvcf, GATKv3_5_HAPLOTYPECALLER.out.normal_germline_gvcf_index)

    // Step NN: Get alignment and WGS metrics
    PICARD_COLLECTALIGNMENTSUMMARYMETRICS(GATK_APPLYBQSR.out.bam)
    PICARD_COLLECTWGSMETRICS(GATK_APPLYBQSR.out.bam)

}



// Function to extract information (meta data + file(s)) from csv file(s)
// https://github.com/nf-core/sarek/blob/master/workflows/sarek.nf#L1084
def extract_csv(csv_file) {

    // check that the sample sheet is not 1 line or less, because it'll skip all subsequent checks if so.
    file(csv_file).withReader('UTF-8') { reader ->
        def line, numberOfLinesInSampleSheet = 0;
        while ((line = reader.readLine()) != null) {numberOfLinesInSampleSheet++}
        if (numberOfLinesInSampleSheet < 2) {
            log.error "Samplesheet had less than two lines. The sample sheet must be a csv file with a header, so at least two lines."
            System.exit(1)
        }
    }

    // Additional check of sample sheet:
    // 1. Each row should specify a lane and the same combination of patient, sample and lane shouldn't be present in different rows.
    // 2. The same sample shouldn't be listed for different patients.
    def patient_sample_lane_combinations_in_samplesheet = []
    def sample2patient = [:]

    Channel.from(csv_file).splitCsv(header: true)
        .map{ row ->
            if (!sample2patient.containsKey(row.sample.toString())) {
                sample2patient[row.sample.toString()] = row.patient.toString()
            } else if (sample2patient[row.sample.toString()] != row.patient.toString()) {
                log.error('The sample "' + row.sample.toString() + '" is registered for both patient "' + row.patient.toString() + '" and "' + sample2patient[row.sample.toString()] + '" in the sample sheet.')
                System.exit(1)
            }
        }

    sample_count_all = 0
    sample_count_normal = 0
    sample_count_tumor = 0

    Channel.from(csv_file).splitCsv(header: true)
        //Retrieves number of lanes by grouping together by patient and sample and counting how many entries there are for this combination
        .map{ row ->
            sample_count_all++
            if (!(row.patient && row.sample)){
                log.error "Missing field in csv file header. The csv file must have fields named 'patient' and 'sample'."
                System.exit(1)
            }
            [[row.patient.toString(), row.sample.toString()], row]
        }.groupTuple()
        .map{ meta, rows ->
            size = rows.size()
            [rows, size]
        }.transpose()
        .map{ row, numLanes -> //from here do the usual thing for csv parsing

        def meta = [:]

        // Meta data to identify samplesheet
        // Both patient and sample are mandatory
        // Several sample can belong to the same patient
        // Sample should be unique for the patient
        if (row.patient) meta.patient = row.patient.toString()
        if (row.sample)  meta.sample  = row.sample.toString()

        // If no sex specified, sex is not considered
        // sex is only mandatory for somatic CNV
        if (row.sex) meta.sex = row.sex.toString()
        else meta.sex = 'NA'

        // If no status specified, sample is assumed normal
        if (row.status) meta.status = row.status.toInteger()
        else meta.status = 0

        if (meta.status == 0) sample_count_normal++
        else sample_count_tumor++

        // join meta to fastq
        if (row.fastq_2) {
            meta.id         = "${row.patient}-${row.sample}".toString()
            def fastq_1     = file(row.fastq_1, checkIfExists: true)
            def fastq_2     = file(row.fastq_2, checkIfExists: true)

            meta.data_type  = 'fastq'

            meta.size       = 1 // default number of splitted fastq

            return [meta.id, meta, [fastq_1, fastq_2]]

        } else {
            log.error "Missing or unknown field in csv file header. Please check your samplesheet"
            System.exit(1)
        }
    }
}