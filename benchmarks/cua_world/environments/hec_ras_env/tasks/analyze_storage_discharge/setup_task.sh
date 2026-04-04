#!/bin/bash
set -e
echo "=== Setting up analyze_storage_discharge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
# This ensures we start with input files but NO result files (forcing the agent to check/run sim)
restore_muncie_project

# 2. Ensure output directory exists and is empty
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/*
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Record initial state
# Check if HEC-RAS results exist (should be false after restore, unless restore script keeps them)
# We strictly delete them to force the agent to run the simulation
rm -f "$MUNCIE_DIR"/*.p04.hdf "$MUNCIE_DIR"/*.p04.tmp.hdf
echo "Cleared previous simulation results."

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Open terminal in project directory
echo "Opening terminal in Muncie project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Type 'ls' to show files
type_in_terminal "ls -lh"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="