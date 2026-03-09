#!/bin/bash
echo "=== Setting up audit_conveyance_monotonicity task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (to populate the HDF5 file with geometry/htabs)
# The HTabs are computed during preprocessing/unsteady run and stored in the .p04.hdf
echo "Checking for HDF5 results..."
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running simulation to generate HDF5 data..."
    run_simulation_if_needed
fi

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Remove any previous output files
rm -f /home/ga/Documents/hec_ras_results/conveyance_audit.json

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Type 'ls' to show files to the agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="