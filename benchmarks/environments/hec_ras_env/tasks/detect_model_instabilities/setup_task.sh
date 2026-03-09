#!/bin/bash
set -e
echo "=== Setting up detect_model_instabilities task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run HEC-RAS if needed)
# We need the .p04.hdf file to be present for the agent to analyze
run_simulation_if_needed

# 3. Setup workspace directories
mkdir -p /home/ga/Documents/hec_ras_results
# Clean up any previous run artifacts to ensure fresh creation
rm -f /home/ga/Documents/hec_ras_results/instability_detector.py
rm -f /home/ga/Documents/hec_ras_results/instability_report.csv
rm -f /home/ga/Documents/hec_ras_results/worst_instability.png

# 4. Record start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# 5. Launch Terminal in the project directory
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type 'ls -lh' to show the agent the HDF file exists
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="