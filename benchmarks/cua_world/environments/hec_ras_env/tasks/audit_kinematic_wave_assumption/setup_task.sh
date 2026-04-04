#!/bin/bash
echo "=== Setting up Audit Kinematic Wave Assumption task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
echo "Restoring Muncie project..."
restore_muncie_project

# 2. Force a clean state by removing simulation results
# The agent MUST run the simulation as part of the task
echo "Cleaning previous simulation results..."
rm -f "$MUNCIE_DIR"/*.p04.hdf
rm -f "$MUNCIE_DIR"/*.p04.tmp.hdf
rm -f "$MUNCIE_DIR"/*.log

# 3. Clean output directory
echo "Preparing output directory..."
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/kinematic_wave_audit.csv"
chown -R ga:ga "$RESULTS_DIR"

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
echo "Initial setup complete" > /tmp/setup_status.txt

# 5. Launch Terminal in Project Directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type a hint command (optional, helps orientation)
type_in_terminal "ls -l"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="