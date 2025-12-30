#!/bin/bash
#SBATCH --job-name=beaufort_jet        #Set the job name to "JobExample1"
#SBATCH -C cpu
#SBATCH --qos=regular 
#SBATCH --time=12:00:00          
#SBATCH --nodes=4
#SBATCH --ntasks=512
#SBATCH --ntasks-per-node=128
#SBATCH --account=m4304
#SBATCH --output=log_500m_no_ice_w_dvd.txt         #Send stdout/err to "Example1Out.[jobID]"

WORK_DIR=/global/homes/d/dylan617/beaufort_jet/
cd $WORK_DIR
source perlmutter_env.sh

OCEAN_IN=${WORK_DIR}/project/ocean_beaufort_jet_bulk_fluxes_no_ice_w_dvd_dx_500m_dz_40_layers.in
ROMS_EXEC=romsM
srun -n 512 ${WORK_DIR}/project/${ROMS_EXEC} ${OCEAN_IN}
