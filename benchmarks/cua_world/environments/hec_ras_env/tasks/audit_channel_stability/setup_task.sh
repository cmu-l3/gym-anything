#!/bin/bash
echo "=== Setting up Audit Channel Stability task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
# This ensures the agent starts with a valid model but no stale results/modifications
restore_muncie_project

# 2. Ensure output directory exists and is empty
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Clean any existing simulation results to force/check if agent runs it
# (Optional: we leave the geometry files, but remove the run results .p04.hdf)
# However, to be nice to the agent and save time, we can leave the simulation results IF
# we want the task to focus purely on analysis. The description says "Run ... (if results not present)".
# Let's remove them to test the "Run" capability.
rm -f "$MUNCIE_DIR"/*.p04.hdf "$MUNCIE_DIR"/*.p04.tmp.hdf

# 4. Record setup timestamp
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Verify HEC-RAS environment is ready in the terminal
type_in_terminal "echo 'Environment Ready. Project: Muncie' && ls -lh"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="