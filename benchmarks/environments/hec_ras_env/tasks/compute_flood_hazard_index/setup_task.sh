#!/bin/bash
set -e
echo "=== Setting up compute_flood_hazard_index task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run unsteady simulation if results don't exist yet
# (The task requires analyzing results, so we ensure they exist to start with)
run_simulation_if_needed

# 3. Setup results directory and clean old files
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/flood_hazard_index.csv"
rm -f "$RESULTS_DIR/flood_hazard_summary.txt"
chown -R ga:ga "$RESULTS_DIR"

# 4. Open a terminal in the project directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 5. Pre-type a helpful hint command (optional, helps context)
# type_in_terminal "ls -lh *.hdf" 

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="