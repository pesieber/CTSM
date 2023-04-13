#!/bin/bash

# Set up
# ------
cosmo_target=cpu

# Clean up
# --------
# cosmo
rm -f YU*
# log
rm -f nout.000000 debug.0[1-2].* core.* *.log
# oasis
rm -f grids.nc masks.nc areas.nc rmp*.nc

# Check
# -----
check_files="cosmo cesm.exe cosmo_env.sh cesm_env.sh"
missing_files=""
for f in ${check_files}; do
    [[ -e $f ]] || missing_files+=" $f"
done
if [[ -n ${missing_files} ]]; then
    echo "ERROR missing file(s):${missing_files}"
    exit 1
fi

# Make missing COSMO directories
# ------------------------------
for ydir in $(sed -n 's/^\s*ydir.*=\s*["'\'']\(.*\)["'\'']\s*/\1/p' INPUT_IO); do
    mkdir -p ${ydir}
done

# Build task dispatch file
# ------------------------
if [[ ${cosmo_target} == cpu ]]; then
    cat > prog_config << EOF
0-23 ./cosmo.sh
24-47 ./cesm.sh
EOF
elif [[ ${cosmo_target} == gpu ]]; then
    cat > prog_config << EOF
0,12,24,36 ./cosmo.sh
1-11,13-23,25-35,37-47 ./cesm.sh
EOF
    
fi

# Submit job
# ----------
sbatch --account=sm61 --time=00:30:00 --nodes=4 --constraint=gpu --partition=debug --job-name=CCLM2 --output="%x.log"  --wrap "srun -u --multi-prog ./prog_config"
