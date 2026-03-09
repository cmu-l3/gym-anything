#!/bin/bash
echo "=== Setting up estimate_wave_celerity_slope task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Ensure simulation results exist (Run HEC-RAS if needed)
# This is critical because the agent needs the HDF file to analyze
run_simulation_if_needed

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
chown ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 6. Type hint command to show available files
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="