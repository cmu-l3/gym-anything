#!/bin/bash
echo "=== Setting up compute_flood_arrival_time task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Ensure simulation results exist (Agent needs them to analyze)
# The task is about ANALYSIS, not running the sim, so we pre-run if needed.
run_simulation_if_needed

# 3. Setup output directory
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
# Remove any existing output to ensure freshness
rm -f "$RESULTS_DIR/flood_arrival_times.csv"

# 4. Record Task Start Time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Terminal in Project Directory
echo "Opening terminal for agent..."
launch_terminal "$MUNCIE_DIR"

# 6. Type hint command to show available files
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="