#!/bin/bash
echo "=== Setting up interpolate_virtual_gauge_results task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Ensure simulation results exist (Run HEC-RAS if needed)
# The task requires analyzing results, so we must guarantee they exist.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Running simulation to generate required HDF5 results..."
    run_simulation_if_needed
fi

# Ensure the .hdf file is accessible (handle the .tmp.hdf vs .hdf naming)
if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    cp "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
fi

# 3. Clean up any previous attempts
rm -rf /home/ga/Documents/hec_ras_results/*
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"
type_in_terminal "ls -lh *.hdf"

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="