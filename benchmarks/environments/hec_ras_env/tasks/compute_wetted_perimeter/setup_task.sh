#!/bin/bash
echo "=== Setting up compute_wetted_perimeter task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Restore Muncie project to clean state
restore_muncie_project

# 3. Prepare results directory (ensure it's empty)
echo "Cleaning results directory..."
rm -rf /home/ga/Documents/hec_ras_results/*
mkdir -p /home/ga/Documents/hec_ras_results
chown ga:ga /home/ga/Documents/hec_ras_results

# 4. Verify HEC-RAS geometry files exist
echo "Verifying geometry files..."
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.g01.hdf" ]; then
    # If the tmp HDF doesn't exist, we might need to run the preprocessor or ensure the base HDF is there
    # For Muncie, usually .p04.tmp.hdf or .g0*.hdf contains geometry
    echo "Listing Muncie files:"
    ls -la "$MUNCIE_DIR"
fi

# 5. Open terminal in the project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Type an introductory command to show files
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Verify screenshot
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Task setup complete ==="