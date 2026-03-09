#!/bin/bash
echo "=== Setting up validate_volume_conservation task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure results directory exists and is empty
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 3. Ensure analysis scripts directory exists (but don't do the work for them)
SCRIPTS_DIR="/home/ga/Documents/analysis_scripts"
mkdir -p "$SCRIPTS_DIR"
chown ga:ga "$SCRIPTS_DIR"

# 4. Remove any existing simulation results to force/check execution
rm -f "$MUNCIE_DIR/Muncie.p04.hdf"
rm -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# 5. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Muncie project restored. Previous results cleared."
echo "Terminal opened in $MUNCIE_DIR"