#!/bin/bash
set -e
echo "=== Setting up export_timeseries_csv task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
echo "Restoring Muncie project..."
restore_muncie_project

# 2. Ensure simulation results exist (Agent needs HDF5 to read from)
# This function (from task_utils.sh) runs RasUnsteady if .p04.hdf is missing
echo "Ensuring simulation results exist..."
run_simulation_if_needed

# 3. Prepare output directory (ensure it's empty)
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
echo "Cleaning results directory: $RESULTS_DIR"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Terminal in Project Directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Verify HDF5 file is visible and valid
if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "HDF5 file confirmed at $MUNCIE_DIR/Muncie.p04.hdf"
    # Create a small hint file or README if needed? 
    # No, instructions are in description. Agent should explore.
else
    echo "ERROR: HDF5 file missing after setup!"
    exit 1
fi

# 7. Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="