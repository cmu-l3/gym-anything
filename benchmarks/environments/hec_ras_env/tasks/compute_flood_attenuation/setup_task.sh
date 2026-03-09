#!/bin/bash
echo "=== Setting up compute_flood_attenuation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to a clean state
# This ensures input files are present but results might be stale/missing
restore_muncie_project

# 2. Clean output directory
echo "Cleaning results directory..."
rm -rf /home/ga/Documents/hec_ras_results/*
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Ensure analysis scripts directory exists (empty, for agent to use)
mkdir -p /home/ga/Documents/analysis_scripts
chown -R ga:ga /home/ga/Documents/analysis_scripts

# 4. Remove the result HDF5 file to force the agent to check/run it
# Or we can leave it if we want to test just the analysis part.
# The task description says "Run ... (if results don't already exist)".
# Let's remove it to force interaction with HEC-RAS binaries or at least checking.
rm -f "$MUNCIE_DIR/Muncie.p04.hdf"
rm -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch Terminal in the project directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project Location: $MUNCIE_DIR"
echo "Output Location: /home/ga/Documents/hec_ras_results"
echo "Task: Run simulation, extract hydrographs, compute attenuation, and report."