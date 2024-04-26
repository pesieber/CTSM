#!/bin/bash

# Script to compile CLM with case-specific settings
# For standalone CLM or coupling with COSMO (for coupling set COMPILER=MY_COMPILER-oasis)
# Domain can be global or regional (set DOMAIN=eur/sa, requires domain file and surface dataset for the desired grid)

set -e # failing commands will cause the shell script to exit

ACCOUNT=s1256

#==========================================
# Case settings
#==========================================

date_1=$(date +'%Y-%m-%d %H:%M:%S')

echo "*** Setting up case ***"

COMPSET=I2000Clm50SpGs # I2000Clm50SpGs for release-clm5.0 (2000_DATM%GSWP3v1_CLM50%SP_SICE_SOCN_MOSART_SGLC_SWAV), I2000Clm50SpRs for CTSMdev (2000_DATM%GSWP3v1_CLM50%SP_SICE_SOCN_SROF_SGLC_SWAV), use SGLC for regional domain!
DOMAIN=eur # eur for CCLM2 (EURO-CORDEX), sa for South-America, glob otherwise
RES=CLM_USRDAT # CLM_USRDAT (custom resolution defined by domain file) for CCLM2, f09_g17 (0.9x1.25) to test glob (inputdata downloaded)
GRID=0.1 # 0.5 or 0.1 for CCLM2 with RES=CLM_USRDAT (for other RES, RES determines the grid)
CODE=clm5.0 # clm5.0 for official release, clm5.0_features for Ronny's version, CTSMdev for latest 
COMPILER=gnu # gnu for gnu/gcc, nvhpc for nvidia/nvhpc; setting to gnu-oasis or nvhpc-oasis will: (1) use different compiler config from .cime, (2) copy oasis source code to CASEDIR
COMPILERNAME=gcc # gcc for gnu/gcc, nvhpc for nvidia/nvhpc; needed to find OASIS installation path
#EXP="cclm2_$(date +'%Y%m%d-%H%M')" # custom case name with date - PS for testing
EXP="clm_EUR11_228cores" # custom case name without date
GRIDNAME=${DOMAIN}_${GRID}
CASENAME=$CODE.$COMPILER.$COMPSET.$RES.$GRIDNAME.$EXP

DRIVER=mct # mct for clm5.0, mct or nuopc for CTSMdev, using nuopc requires ESMF installation (>= 8.2.0)
MACH=pizdaint
QUEUE=normal # USER_REQUESTED_QUEUE, overrides default JOB_QUEUE
WALLTIME="00:30:00" # USER_REQUESTED_WALLTIME, overrides default JOB_WALLCLOCK_TIME, "00:20:00" for testing
PROJ=sm61 # extract project name (e.g. sm61)
NNODES=19 # number of nodes
NCORES=$(( NNODES * 12 )) # 12 cores per node (default MAX_MPITASKS_PER_NODE=12, was called NTASKS before, sets number of CPUs)
NSUBMIT=0 # partition into smaller chunks, excludes the first submission
STARTDATE="2000-01-01"
#NYEARS=1
NHOURS=120 # PS - for testing, run for 5x 24h and write hourly output (see user_nl_clm); for 1 year need to change here, STOP_OPTION and output

# Set directories
export CLMROOT=$PWD # CLM code base directory on $PROJECT where this script is located
export CCLM2ROOT=$CLMROOT/.. # CCLM2 code base directory on $PROJECT where CLM, OASIS and COSMO are located
export CASEDIR=$SCRATCH/CCLM2_cases/$CASENAME # case directory on scratch
export CESMDATAROOT=$SCRATCH/CCLM2_inputdata # inputdata directory on scratch (to reuse, includes downloads and preprocessed EURO-CORDEX files)
export CESMOUTPUTROOT=$SCRATCH/CCLM2_output/$CASENAME # output directory on scratch

# Log output (use "tee" to send output to both screen and $outfile)
logfile=$SCRATCH/CCLM2_logs/${CASENAME}_mylogfile.log
mkdir -p "$(dirname "$logfile")" && touch "$logfile" # create parent/child directories and logfile
cp $CLMROOT/$BASH_SOURCE $SCRATCH/CCLM2_logs/${CASENAME}_myjobscipt.sh # copy this script to logs
print_log() {
    output="$1"
    echo -e "${output}" | tee -a $logfile
}

print_log "*** Case at: ${CASEDIR} ***"
print_log "*** Case settings: compset ${COMPSET}, resolution ${RES}, domain ${DOMAIN}, compiler ${COMPILER} ***"
print_log "*** Logfile at: ${logfile} ***"

# Sync inputdata on scratch because scratch will be cleaned every month (change inputfiles on $PROJECT!)
print_log "\n*** Syncing inputdata on scratch  ***"
rsync -av /project/$PROJ/shared/CCLM2_inputdata/ $CESMDATAROOT/ | tee -a $logfile # also check for updates in file content (there are many unnecessary files now so we may want to clean up!)
#sbatch --account=$PROJ --export=ALL,PROJ=$PROJ transfer_clm_inputdata.sh # xfer job to prevent overflowing the loginnode


#==========================================
# Load modules and find spack packages
#==========================================

# Load modules: now done through $USER/.cime/config_machines.xml
# print_log "*** Loading modules ***"
# daint-gpu (although CLM will run on cpus)
# PrgEnv-xxx (also switch compiler version if needed)
# cray-mpich
# cray-python
# cray-netcdf-hdf5parallel
# cray-hdf5-parallel
# cray-parallel-netcdf

#module list | tee -a $logfile

# Find spack_oasis installation (used in .cime/config_compilers.xml)
if [[ $COMPILER =~ "oasis" ]]; then
    print_log "\n*** Finding spack_oasis ***"
    export OASIS_PATH=$(spack location -i oasis%${COMPILERNAME}+fix_mct_conflict) # e.g. /project/sm61/psieber/spack-install/oasis/master/gcc/24obfvejulxnpfxiwatzmtcddx62pikc
    print_log "OASIS at: ${OASIS_PATH}"
fi

# Find spack_esmf installation (used in .cime/config_machines.xml and env_build.xml)
# Running with esmf@8.4.1 available with spack but not c2sm-spack
if [ $DRIVER == nuopc ]; then
    print_log "\n *** Finding spack_esmf ***"
    export ESMF_PATH=$(spack location -i esmf@8.2.0%$COMPILERNAME) # e.g. /project/sm61/psieber/spack-install/esmf-8.1.1/gcc-9.3.0/3iv2xwhfgfv7fzpjjayc5wyk5osio5c4
    print_log "ESMF at: ${ESMF_PATH}"
fi


#==========================================
# Create case
#==========================================

print_log "\n*** Creating CASE: ${CASENAME} ***"

cd $CLMROOT/cime/scripts
./create_newcase --case $CASEDIR --compset $COMPSET --res $RES --mach $MACH --compiler $COMPILER --driver $DRIVER --project $ACCOUNT --run-unsupported | tee -a $logfile


#==========================================
# Configure CLM
# Settings will appear in namelists and have precedence over user_nl_xxx
#==========================================

print_log "\n*** Modifying env_*.xml  ***"
cd $CASEDIR

# Set directory structure
./xmlchange RUNDIR="$CASEDIR/run" # by defaut, RUNDIR is $SCRATCH/$CASENAME/run
./xmlchange EXEROOT="$CASEDIR/bld"

# Change job settings (env_batch.xml or env_workflow.xml). Do this here to change for both case.run and case.st_archive
./xmlchange JOB_QUEUE=$QUEUE --force
./xmlchange JOB_WALLCLOCK_TIME=$WALLTIME
./xmlchange PROJECT=$ACCOUNT

# Set run start/stop options and DATM forcing (env_run.xml)
./xmlchange RUN_TYPE=startup
./xmlchange RESUBMIT=$NSUBMIT
./xmlchange RUN_STARTDATE=$STARTDATE
#./xmlchange STOP_OPTION=nyears,STOP_N=$NYEARS
./xmlchange STOP_OPTION=nhours,STOP_N=$NHOURS # PS - for testing
./xmlchange NCPL_BASE_PERIOD="day",ATM_NCPL=48 # coupling freq default 30min = day,48
YYYY=${STARTDATE:0:4}
if [ $CODE == CTSMdev ] && [ $DRIVER == nuopc ]; then
    # new variable names in CTSMdev with nuopc driver
    ./xmlchange DATM_YR_START=${YYYY},DATM_YR_END=${YYYY},DATM_YR_ALIGN=${YYYY}
else
    # in clm5.0 and CLM_features, with any driver
    ./xmlchange DATM_CLMNCEP_YR_START=${YYYY},DATM_CLMNCEP_YR_END=${YYYY},DATM_CLMNCEP_YR_ALIGN=${YYYY}
fi

# Additional options
./xmlchange CCSM_BGC=CO2A,CLM_CO2_TYPE=diagnostic,DATM_CO2_TSERIES=20tr # historical transient CO2 sent from atm to land (as for LUCAS); default is CLM_CO2_TYPE=constant, co2_ppmv = 367.0
#./xmlchange use_lai_streams=.true. # default is false (climatology as for LUCAS); does not work with xmlchange, change manually in lnd_in

# Set the number of cores, nodes will be COST_PES/12 per default (env_mach_pes.xml)
./xmlchange COST_PES=$NCORES # number of cores=CPUs
./xmlchange NTASKS=$NCORES # number of tasks for each component (can be set with $NCORES or -$NNODES for same result)

# If parallel netcdf is used, PIO_VERSION="2" (have not gotten this to work!)
#./xmlchange PIO_VERSION="1" # 1 is default in clm5.0, 2 is default in CTSMdev (both only work with defaults)

# Activate debug mode (env_build.xml)
# ./xmlchange DEBUG=TRUE
# ./xmlchange INFO_DBUG=3 # Change amount of output

# Domain and mapping files for regional cases
if [ $RES == CLM_USRDAT ]; then 
    ./xmlchange CLM_USRDAT_NAME=$GRIDNAME # needed if RES=CLM_USRDAT
fi

if [ $DOMAIN == eur ]; then
    REGDOMAIN_PATH="$CESMDATAROOT/CCLM2_EUR_inputdata/domain"
    if [ $GRID == 0.5 ]; then
        REGDOMAIN_FILE="domain_EU-CORDEX_${GRID}_lon360.nc"
    elif [ $GRID == 0.1 ]; then
        REGDOMAIN_FILE="domain_EUR11_lon360_reduced.nc"
    fi
fi

if [ $DOMAIN == sa ]; then
    REGDOMAIN_PATH="$CESMDATAROOT/CCLM2_SA_inputdata/domain"
    REGDOMAIN_FILE="domain.lnd.360x720_SA-CORDEX_cruncep.100429.nc"
fi

if [ $DOMAIN == eur ] || [ $DOMAIN == sa ]; then
    ./xmlchange LND_DOMAIN_PATH=$REGDOMAIN_PATH,ATM_DOMAIN_PATH=$REGDOMAIN_PATH # have to be identical for LND and ATM
    ./xmlchange LND_DOMAIN_FILE=$REGDOMAIN_FILE,ATM_DOMAIN_FILE=$REGDOMAIN_FILE
    ./xmlchange MOSART_MODE=NULL # turn off MOSART because it runs globally
    # Not needed for stub/off components (these files are global), leave as default=idmap
    #./xmlchange LND2GLC_FMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_360x720_TO_gland4km_aave.170429.nc" 
    #./xmlchange LND2GLC_SMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_360x720_TO_gland4km_aave.170429.nc"
    #./xmlchange GLC2LND_FMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_gland4km_TO_360x720_aave.170429.nc"
    #./xmlchange GLC2LND_SMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_gland4km_TO_360x720_aave.170429.nc"
    #./xmlchange LND2ROF_FMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_360x720_nomask_to_0.5x0.5_nomask_aave_da_c130103.nc"
    #./xmlchange ROF2LND_FMAPNAME="$CESMDATAROOT/CCLM2_EUR_inputdata/mapping/map_0.5x0.5_nomask_to_360x720_nomask_aave_da_c120830.nc" 
fi

# ESMF (env_build.xml)
./xmlchange --file env_build.xml --id COMP_INTERFACE --val $DRIVER # mct is default in clm5.0, nuopc is default in CTSMdev (requires ESMF installation); adding --driver mct to create_newcase adds everything needed
if [ $DRIVER == mct ]; then    
    ./xmlchange --file env_build.xml --id USE_ESMF_LIB --val "FALSE" # FALSE is default in clm5.0; since cesm1_2 ESMF is no longer necessary to run with calendar=gregorian
elif [ $DRIVER == nuopc ]; then
    ./xmlchange --file env_build.xml --id USE_ESMF_LIB --val "TRUE" # using the ESMF library specified by env var ESMFMKFILE (config_machines.xml), or ESMF_LIBDIR (not found in env_build.xml)
fi


#==========================================
# Set up the case (creates user_nl_xxx)
#==========================================

print_log "\n*** Running case.setup ***"
./case.setup -r | tee -a $logfile


#==========================================
# User namelists (use cat >> to append)
# Surface data: domain-specific 
# Paramfile: use default
# Domainfile: has to be provided to DATM
#==========================================

print_log "\n*** Modifying user_nl_*.xml  ***"

if [ $GRIDNAME == eur_0.5 ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/CCLM2_EUR_inputdata/surfdata/surfdata_0.5x0.5_hist_16pfts_Irrig_CMIP6_simyr2000_c190418.nc"
EOF
elif [ $GRIDNAME == eur_0.1 ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/CCLM2_EUR_inputdata/surfdata/surfdata_0.1x0.1_EUR11_hist_16pfts_Irrig_CMIP6_simyr2005_c230523.nc"
EOF
fi

if [ $DOMAIN == sa ]; then
cat >> user_nl_clm << EOF
fsurdat = "$CESMDATAROOT/CCLM2_SA_inputdata/surfdata/surfdata_360x720cru_SA-CORDEX_16pfts_Irrig_CMIP6_simyr2000_c170824.nc"
EOF
fi

# For global domain keep the defaults (downloaded from svn trunc to CESMDATAROOT/cesm_inputdata and reused)

# Namelist options available in Ronny's code
# requires additional variables in the surfdata, e.g. dbh for biomass_heat_storage
#if [ $CODE == clm5.0_features ]; then
#cat >> user_nl_clm << EOF
#use_biomass_heat_storage = .true.
#use_individual_pft_soil_column = .true.
#zetamaxstable = 100.0d00
#EOF
#fi

# Namelist options available in CTSMdev (?)
#if [ $CODE == CTSMdev ]; then
#cat >> user_nl_clm << EOF
#use_biomass_heat_storage = .true.
#z0param_method = 'Meier2022'
#zetamaxstable = 100.0d00
#use_z0mg_2d = .true.
#use_z0m_snowmelt = .true.
#flanduse_timeseries=''
#EOF
#fi

# Output frequency and averaging (example)
# hist_empty_htapes = .true. # turn off all default output on h0
# hist_fincl1 or hist_fexcl1 # include or exclude selected variables
# hist_nhtfrq # output frequency
# hist_mfilt # number of values per file
# hist_avgflag_pertape # averaging over the output interval
# hist_dov2xy # true for 2D (grid cell level), false for 1D vector (pft, column or landunit output)
# hist_type1d_pertape # Averaging for 1D vector output (when hist_dov2xy is false): average to 'GRID', 'LAND', 'COLS', 'PFTS'; ' ' for 2D and no averaging (i.e. PFT output)

# Commented out during testing to avoid lots of output

# For testing: remove default history fields, write monthly (0), daily (-24) or hourly (-1) (temperatures and surface fluxes SWdn, SWup, LWdn, LWup, SH, LH, G)
# hourly grid cell, daily pft level output
cat >> user_nl_clm << EOF
hist_empty_htapes = .true.
hist_fincl1 = 'FSDS','FSR','FLDS','FIRE','EFLX_LH_TOT','FSH','QFLX_EVAP_TOT','QSOIL','QVEGE','QVEGT','QOVER','QDRAI','SOILLIQ','SOILICE','FSNO','SNOW_DEPTH','TSOI','FPSN','TV','TG','TSKIN','TSA','TREFMNAV','TREFMXAV','TBOT','QIRRIG'
hist_fincl2 = 'TSKIN','TBOT'
hist_fincl3 = 'TSKIN','TBOT' 
hist_fincl4 = 'FSDS','FSR','FLDS','FIRE','EFLX_LH_TOT','FSH'
hist_fincl5 = 'TSKIN','TSA','TREFMNAV','TREFMXAV','TBOT'
hist_nhtfrq = -24,-24,-24,-3,0
hist_mfilt  = 365,365,365,2920,12
hist_avgflag_pertape = 'A','M','X','A','A'
hist_dov2xy = .true.,.true.,.true.,.true.,.true.
EOF


#==========================================
# For OASIS coupling: before building, add the additional routines for OASIS interface in your CASEDIR on scratch
#==========================================

if [[ $COMPILER =~ "oasis" ]]; then
    print_log "\n*** Adding OASIS routines ***"
    ln -sf $CCLM2ROOT/cesm2_oasis/src/oas/* SourceMods/src.drv/
    rm SourceMods/src.drv/oas_clm_vardef.F90
    ln -sf $CCLM2ROOT/cesm2_oasis/src/drv/* SourceMods/src.drv/
    ln -sf $CCLM2ROOT/cesm2_oasis/src/oas/oas_clm_vardef.F90 SourceMods/src.share/
    ln -sf $CCLM2ROOT/cesm2_oasis/src/datm/* SourceMods/src.datm/
fi


#==========================================
# Build
#==========================================

print_log "\n*** Building case ***"
./case.build --clean-all | tee -a $logfile

if [ $CODE == clm5.0_features ]; then
    ./case.build --skip-provenance-check | tee -a $logfile # needed with Ronny's old code base
else
    ./case.build | tee -a $logfile
fi

print_log "\n*** Finished building new case in ${CASEDIR} ***"


#==========================================
# Check and download input data
#==========================================

print_log "\n*** Downloading missing inputdata (if needed) ***"
print_log "Consider transferring new data to PROJECT, e.g. rsync -av ${SCRATCH}/CCLM2_inputdata/ /project/${PROJ}/shared/CCLM2_inputdata/"
./check_input_data --download


#==========================================
# FOR OASIS coupling: after building, add OASIS_dummy and streams in your run directory on scratch
# These files are required by DATM to use the forcing from COSMO instad of GSWP 
#==========================================

if [[ $COMPILER =~ "oasis" ]]; then
    print_log "\n*** Adding OASIS_dummy files ***"
    
    # Copy the streams file (used for any domain and resolution)
    cp $CESMDATAROOT/CCLM2_EUR_inputdata/OASIS_dummy_for_datm/OASIS.stream.txt run/
    #cp $CESMDATAROOT/CCLM2_EUR_inputdata/OASIS_dummy_for_datm/datm.streams.txt.co2tseries.20tr run/
    
    # Modify datm_in to include OASIS streams (cannot be done with user_nl_datm)
    sed -i -e '/dtlimit/,$d' run/datm_in # keep first part of generated datm_in (until domainfile path), modify in place
    sed -e '1,/domainfile/d' $CESMDATAROOT/CCLM2_EUR_inputdata/OASIS_dummy_for_datm/datm_in_copy_streams >> run/datm_in # append second part of CCLM2 datm_in (anything after domainfile path)
    
    # Copy the OASIS dummy (domain and resolution specific)
    if [ $DOMAIN == eur ]; then
        cp $CESMDATAROOT/CCLM2_EUR_inputdata/OASIS_dummy_for_datm/OASIS_dummy_${GRID}_lon360.nc run/OASIS_dummy.nc
    else
        raise error "OASIS_dummy.nc is missing for this domain" | tee -a $logfile
    fi
fi


#==========================================
# Preview and submit job
#==========================================

print_log "\n*** Preview the run ***"
./preview_run | tee -a $logfile

print_log "*** Loaded modules for build from .cime, passed to env_mach_specific.xml, used for run ***"
print_log "Check in ${CASEDIR}/software_environment.txt"

print_log "\n*** Submitting job ***"
./case.submit -a "-C gpu" | tee -a $logfile

# fails for clm5.0_features because tasks-per-node evaluates to float (12.0) with python 3. Cannot find where the calculation is made. Can also not override it like this:
# ./case.submit -a "-C gpu -p normal --ntasks-per-node 12" 
# or by setting in config_batch.xml

squeue --user=$USER | tee -a $logfile
#less CaseStatus

date_2=$(date +'%Y-%m-%d %H:%M:%S')
duration=$SECONDS
print_log "Started at: ${date_1}"
print_log "Finished at: ${date_2}"
print_log "Duration to create, setup, build, submit: $(($duration / 60)) min $(($duration % 60)) sec"

print_log "\n*** Check the job: squeue --user=${USER} ***"
print_log "*** Check the case: in ${CASEDIR}, run less CaseStatus ***"
print_log "*** Output at: ${CESMOUTPUTROOT} ***"


#==========================================
# Copy final CaseStatus to logs
#==========================================

# Notes:
#env_case = model version, components, resolution, machine, compiler [do not modify]
#env_mach_pes = NTASKS, number of MPI tasks (or nodes if neg. values) [modify before setup]
#env_mach_specific = controls machine specific environment [modify before setup]
#env_build = component settings [modify before build]
#env_batch = batch job settings [modify any time]
#env_run = run settings incl runtype, coupling, pyhsics/sp/bgc and output [modify any time]
#env_workflow = walltime, queue, project
