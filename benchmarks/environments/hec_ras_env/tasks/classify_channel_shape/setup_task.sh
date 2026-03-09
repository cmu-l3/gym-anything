#!/bin/bash
set -e
echo "=== Setting up Classify Channel Shape Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Setup Directories
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
# Ensure directory is empty and owned by ga
rm -rf "$RESULTS_DIR"/*
chown -R ga:ga "$RESULTS_DIR"

# 2. Restore Muncie Project to clean state
restore_muncie_project

# 3. Record initial state of simulation results
# We want to verify the agent actually runs the simulation
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
if [ -f "$HDF_FILE" ]; then
    # If it exists, record mtime. If it doesn't, mtime is 0.
    STAT_CMD="stat -c %Y $HDF_FILE"
    INITIAL_MTIME=$($STAT_CMD 2>/dev/null || echo "0")
else
    INITIAL_MTIME="0"
fi
echo "$INITIAL_MTIME" > /tmp/initial_hdf_mtime.txt

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Terminal in Project Directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Create a blank python script template to hint at tool usage (optional helper)
# We won't write the code, just create the file to reduce friction
touch "$RESULTS_DIR/calculate_shape.py"
chown ga:ga "$RESULTS_DIR/calculate_shape.py"

# 7. Initial Screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="