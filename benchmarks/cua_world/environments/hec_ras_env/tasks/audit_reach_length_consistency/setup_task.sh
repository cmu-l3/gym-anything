#!/bin/bash
set -e
echo "=== Setting up audit_reach_length_consistency task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure HDF5 exists (Run simulation if needed to generate Muncie.p04.tmp.hdf)
# The environment install might have cleaned it, or it might be stale.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Generating HDF5 files..."
    # We can try to run the geometry preprocessor or just the unsteady run
    # RasUnsteady is safer to ensure full HDF structure
    run_simulation_if_needed
fi

# Ensure the specific file expected by description exists
if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    cp "$MUNCIE_DIR/Muncie.p04.hdf" "$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

# 3. Create results directory
mkdir -p /home/ga/Documents/hec_ras_results
# Clear previous results if any
rm -f /home/ga/Documents/hec_ras_results/reach_length_audit.csv
rm -f /home/ga/Documents/hec_ras_results/audit_summary.txt
rm -f /home/ga/Documents/hec_ras_results/audit_reach_lengths.py

# 4. Set permissions
chown -R ga:ga /home/ga/Documents/hec_ras_projects
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 5. Record start time and initial state
date +%s > /tmp/task_start_time.txt
# Record hash of HDF to ensure it wasn't tampered with (optional but good)
md5sum "$MUNCIE_DIR/Muncie.p04.tmp.hdf" > /tmp/hdf_initial_hash.txt

# 6. Open terminal in the project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="