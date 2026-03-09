#!/bin/bash
set -e
echo "=== Setting up compute_stage_area_curve task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Restore Muncie project to clean state
restore_muncie_project

# 3. Run simulation to ensure HDF results/geometry exist
# The task relies on reading geometry from the output HDF (or input HDF if generated)
# Running the simulation ensures Muncie.p04.hdf is present and populated
run_simulation_if_needed

# 4. Clean up any previous results to ensure we detect new files
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -f "$RESULTS_DIR/stage_area_curve.csv"
rm -f "$RESULTS_DIR/cross_section_info.txt"
rm -f "$RESULTS_DIR/stage_area_plot.png"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# 5. Launch terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type a helpful hint command (optional, but helps context)
# Shows available HDF files and Python availability
type_in_terminal "ls -lh *.hdf && python3 --version"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="