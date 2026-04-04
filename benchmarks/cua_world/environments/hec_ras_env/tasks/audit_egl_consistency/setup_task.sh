#!/bin/bash
echo "=== Setting up Audit EGL Consistency task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist
# The task requires analyzing results, so we must run the simulation first if p04.hdf doesn't exist
run_simulation_if_needed

# 3. Ensure output directory exists and is empty of previous results
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/egl_profile_audit.csv"
rm -f "$RESULTS_DIR/audit_summary.txt"
chown -R ga:ga "$RESULTS_DIR"

# 4. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 5. Provide a hint/check file in the terminal
type_in_terminal "ls -lh Muncie.p04.hdf"

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="