#!/bin/bash
echo "=== Setting up Audit Friction Slope Consistency task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. CLEAR existing simulation results to force the agent to run the simulation
# This ensures the agent performs the "Run Simulation" step and works with fresh data
echo "Clearing existing simulation results..."
rm -f "$MUNCIE_DIR/Muncie.p04.hdf"
rm -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 3. Setup output directory
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/roughness_audit.csv"
chown -R ga:ga "$RESULTS_DIR"

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open a terminal in the Muncie directory
# The agent needs to run RasUnsteady from here or write a script
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Show the files to the agent to confirm state
type_in_terminal "ls -lh"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Project: Muncie (Clean State)"
echo "Action Required: Run Unsteady Simulation -> Audit Results"