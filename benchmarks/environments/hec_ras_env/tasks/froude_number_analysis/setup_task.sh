#!/bin/bash
set -e
echo "=== Setting up Froude Number Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Muncie.p04.hdf)
# This is critical as the agent needs to read this file
run_simulation_if_needed

# Verify the HDF file is actually there
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
if [ ! -f "$HDF_FILE" ]; then
    echo "ERROR: Simulation failed to produce output HDF file."
    exit 1
fi

# 3. Clean up previous results to ensure fresh creation
echo "Cleaning output directory..."
rm -f "$RESULTS_DIR"/froude_analysis.csv
rm -f "$RESULTS_DIR"/froude_report.txt
mkdir -p "$RESULTS_DIR"

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in the project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Display available files to the agent in the terminal
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Results file available at: $HDF_FILE"
echo "Ready for analysis."