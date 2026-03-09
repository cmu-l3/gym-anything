#!/bin/bash
echo "=== Setting up compute_specific_energy task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist
# This is critical as the task requires analyzing existing results
run_simulation_if_needed

# 3. Setup directories
mkdir -p /home/ga/Documents/hec_ras_results
# Clear any previous run artifacts
rm -f /home/ga/Documents/hec_ras_results/specific_energy_curve.csv
rm -f /home/ga/Documents/hec_ras_results/specific_energy_report.txt

# 4. Record task start time and initial state
date +%s > /tmp/task_start_time.txt
# Record checksum of the HDF file to ensure agent analyzes the correct file
md5sum "$MUNCIE_DIR/Muncie.p04.hdf" > /tmp/hdf_checksum.txt 2>/dev/null || true

# 5. Open terminal in project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show file structure to agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="