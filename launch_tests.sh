#!/bin/bash

#SBATCH --job-name=EndTest_CS_nextflow
#SBATCH -p compute
#SBATCH -q batch
#SBATCH -t 72:00:00
#SBATCH --mem=10G
#SBATCH --ntasks=1
#SBATCH --output=log_nf_test_%j.out

cd $SLURM_SUBMIT_DIR

module use --append /projects/omics_share/meta/modules
module load nextflow/23.10.1

nf-test test --tap nf-test-report-$SLURM_JOB_ID.out --verbose

nf-test clean
