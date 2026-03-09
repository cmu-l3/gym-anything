#!/bin/bash
set -e
echo "=== Setting up compute_shear_stress task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"

# 1. Restore clean Muncie project
echo "Restoring Muncie project..."
restore_muncie_project

# 2. Clean and recreate results directory
echo "Cleaning results directory..."
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# 3. Ensure simulation results exist (Agent should be able to run it, but we ensure state is consistent)
# We won't run it for them, but we ensure the *environment* is ready for them to run it.
# However, to avoid "file locked" issues or partial states, we remove any stale tmp files.
rm -f "$MUNCIE_DIR"/*.tmp.hdf
rm -f "$MUNCIE_DIR"/*.p04.hdf

# 4. Open terminal in project directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# 6. Record initial file counts for anti-gaming
ls -1 "$RESULTS_DIR" | wc -l > /tmp/initial_file_count.txt

echo "=== Task setup complete ==="