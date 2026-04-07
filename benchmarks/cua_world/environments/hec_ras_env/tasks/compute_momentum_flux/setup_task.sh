#!/bin/bash
set -e
echo "=== Setting up compute_momentum_flux task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Setup/Restore Muncie Project
# This ensures we have a clean state and valid HDF5 results
echo "Restoring Muncie project..."
restore_muncie_project

# 3. Ensure simulation results exist
# The task requires analyzing results, so we must guarantee they exist.
# If Muncie.p04.hdf doesn't exist, we run the simulation.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Running HEC-RAS simulation to generate results..."
    run_simulation_if_needed
fi

# Ensure the HDF file is accessible
HDF_FILE=$(find "$MUNCIE_DIR" -name "Muncie.p04*.hdf" | head -n 1)
if [ -z "$HDF_FILE" ]; then
    echo "ERROR: Failed to generate HDF5 results file."
    # Try one last ditch effort to copy from backup if simulation failed
    if [ -f "/opt/hec-ras/examples/Muncie/Muncie.p04.hdf" ]; then
        cp "/opt/hec-ras/examples/Muncie/Muncie.p04.hdf" "$MUNCIE_DIR/"
    fi
fi

# 4. Create results directory (empty)
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 5. Open Terminal in Project Directory
# The agent needs to see the files to know where to start
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type 'ls' to show the user the HDF file exists
type_in_terminal "ls -lh *.hdf"

# 7. Maximize terminal for visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="