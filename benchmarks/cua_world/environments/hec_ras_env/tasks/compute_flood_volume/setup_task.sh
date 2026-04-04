#!/bin/bash
echo "=== Setting up compute_flood_volume task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure valid HDF5 results exist
# This ensures Muncie.p04.hdf is present and valid
run_simulation_if_needed

# 3. Clean up previous attempt artifacts (if any)
rm -f /home/ga/Documents/analysis_scripts/compute_flood_volume.py
rm -f /home/ga/Documents/hec_ras_results/flood_volume_report.txt
mkdir -p /home/ga/Documents/analysis_scripts
mkdir -p /home/ga/Documents/hec_ras_results

# 4. Open terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Type a helpful hint command to list files
type_in_terminal "ls -lh *.hdf"

# 6. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="