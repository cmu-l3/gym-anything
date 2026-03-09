#!/bin/bash
echo "=== Setting up compute_hydraulic_geometry task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Setup results directory (ensure it's empty)
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Open a terminal in the Muncie directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. List files to give context
type_in_terminal "ls -lh Muncie.*"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="