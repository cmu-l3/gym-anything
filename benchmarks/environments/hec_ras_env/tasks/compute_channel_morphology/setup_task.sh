#!/bin/bash
echo "=== Setting up compute_channel_morphology task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Muncie.p04.hdf)
# The task relies on HDF5 data being present.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running simulation to generate HDF5 results..."
    run_simulation_if_needed
fi

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
# Remove any previous result
rm -f /home/ga/Documents/hec_ras_results/morphology_metrics.json

# 5. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show files to the agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="