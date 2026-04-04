#!/bin/bash
echo "=== Setting up extract_longitudinal_profile task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Setup Results Directory (Ensure it's empty)
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# 3. Prepare the Muncie directory
# Ensure input files are ready but results (p04.hdf) are NOT pre-calculated to force agent to check/run
# Note: The 'restore_muncie_project' utility might copy a completed HDF if source has it.
# We will explicitly remove the result HDF to force the agent to run the simulation,
# or at least verify the 'run if needed' part of the prompt.
rm -f "$MUNCIE_DIR/Muncie.p04.hdf"

# 4. Open Terminal in Project Directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project Location: $MUNCIE_DIR"
echo "Results Location: $RESULTS_DIR"