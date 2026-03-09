#!/bin/bash
set -e
echo "=== Setting up compute_inundation_width task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure HDF results exist
# The description says "simulation has been run", so we must ensure it.
echo "Ensuring simulation results exist..."
run_simulation_if_needed

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
# Remove any existing answer files
rm -f /home/ga/Documents/hec_ras_results/inundation_width.csv
rm -f /home/ga/Documents/hec_ras_results/inundation_summary.txt

chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show the files to the agent
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="