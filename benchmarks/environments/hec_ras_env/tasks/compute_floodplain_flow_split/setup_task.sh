#!/bin/bash
echo "=== Setting up compute_floodplain_flow_split task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure HDF results exist (Critical for this task)
# The task requires analyzing results, so we must ensure they exist first.
run_simulation_if_needed

# 3. Setup output directories
mkdir -p /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/analysis_scripts
rm -f /home/ga/Documents/hec_ras_results/flow_distribution.csv
rm -f /home/ga/Documents/hec_ras_results/flow_split_summary.txt
rm -f /home/ga/Documents/hec_ras_results/flow_split_analysis.py

# 4. Open terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Provide a hint by listing files
type_in_terminal "ls -lh *.hdf"

# 6. Record start time and initial state
date +%s > /tmp/task_start_time.txt
# Record HDF file timestamp to ensure agent uses the current one
stat -c %Y "$MUNCIE_DIR/Muncie.p04.hdf" > /tmp/hdf_mtime_start.txt 2>/dev/null || echo "0" > /tmp/hdf_mtime_start.txt

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="