#!/bin/bash
set -e
echo "=== Setting up identify_overbank_flow task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup User Directories
mkdir -p /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/hec_ras_projects/Muncie

# 2. Restore Muncie Project (Clean State)
restore_muncie_project

# 3. Ensure Simulation Results Exist
# The task requires analyzing results, so we must run the simulation if .p04.tmp.hdf doesn't exist.
# Note: In Muncie example, the output might be .p04.hdf or .p04.tmp.hdf depending on run state.
# We will ensure Muncie.p04.tmp.hdf exists as that is what standard RasUnsteady produces.

HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

if [ ! -f "$HDF_FILE" ]; then
    echo "Running HEC-RAS simulation to generate required HDF5 results..."
    
    # Run geometry preprocessor
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasGeomPreprocess Muncie.g04" > /dev/null 2>&1 || true
    
    # Run Unsteady
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /tmp/ras_run.log 2>&1
    
    if [ ! -f "$HDF_FILE" ]; then
        echo "ERROR: Simulation failed to produce $HDF_FILE"
        cat /tmp/ras_run.log
        exit 1
    fi
    echo "Simulation complete."
else
    echo "Simulation results already exist."
fi

# 4. Anti-gaming Timestamp
date +%s > /tmp/task_start_time.txt
# Also record output directory state
ls -laR /home/ga/Documents/hec_ras_results > /tmp/initial_results_state.txt

# 5. Open Terminal for Agent
launch_terminal "$MUNCIE_DIR"
type_in_terminal "ls -lh Muncie.p04.tmp.hdf"

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="