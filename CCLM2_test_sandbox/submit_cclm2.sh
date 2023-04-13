#!/bin/bash

# Clean up
# --------
# cosmo
rm -f YU*
# log
rm -f nout.000000 debug.0[1-2].* core.* cesm*.log cosmo*.log
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
cat > prog_config << EOF
0-23 ./cesm.sh > cesm.log
24-47 ./cosmo.sh > cosmo.log
EOF

# Submit job
# ----------
sbatch --account=sm61 --time=00:30:00 --nodes=4 --constraint=gpu --partition=debug --job-name=CCLM2 --output="%x.log"  --wrap "srun -u --multi-prog ./prog_config"
