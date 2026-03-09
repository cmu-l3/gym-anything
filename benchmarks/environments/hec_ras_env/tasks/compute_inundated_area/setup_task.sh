#!/bin/bash
set -e
echo "=== Setting up compute_inundated_area task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Directories
mkdir -p /home/ga/Documents/hec_ras_results
chown ga:ga /home/ga/Documents/hec_ras_results
# Clear any previous results
rm -f /home/ga/Documents/hec_ras_results/*

# 2. Restore clean Muncie project
restore_muncie_project

# 3. Ensure Simulation Results Exist
# The agent needs the HDF5 file to do the analysis.
# We run it now to ensure a deterministic starting state with valid results.
echo "Ensuring HEC-RAS simulation results exist..."
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    run_simulation_if_needed
fi

# Ensure permissions
chown -R ga:ga "$MUNCIE_DIR"

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
# Record checksum of HDF file to ensure agent analyzes the correct one
md5sum "$MUNCIE_DIR/Muncie.p04.hdf" > /tmp/initial_hdf_checksum.txt

# 5. Launch Terminal
echo "Opening terminal for agent..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type some helpful commands (optional, to help agent orient)
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="