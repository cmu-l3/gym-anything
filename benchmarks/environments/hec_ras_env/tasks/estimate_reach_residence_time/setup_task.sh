#!/bin/bash
set -e
echo "=== Setting up estimate_reach_residence_time task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run HEC-RAS if needed)
# The task requires analyzing results, not running the sim, so we ensure results exist.
run_simulation_if_needed

# 3. Create results directory
mkdir -p /home/ga/Documents/hec_ras_results
# Clean up any previous attempts
rm -f /home/ga/Documents/hec_ras_results/volume_integration.csv
rm -f /home/ga/Documents/hec_ras_results/residence_time_report.txt
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Launch Terminal in Project Directory
launch_terminal "$MUNCIE_DIR"

# 5. Type a hint/greeting in the terminal
type_in_terminal "echo 'Ready to analyze Muncie.p04.hdf using Python...'"

# 6. Maximize terminal for visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="