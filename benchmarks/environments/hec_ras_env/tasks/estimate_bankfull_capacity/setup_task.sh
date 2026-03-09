#!/bin/bash
echo "=== Setting up estimate_bankfull_capacity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to produce results (if not already present)
# This ensures the agent has a valid HDF5 file to analyze immediately
run_simulation_if_needed

# 3. Create output directory and clean state
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/bankfull_capacity.csv
rm -f /home/ga/Documents/hec_ras_results/*.py
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Open a terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Hint: List the HDF files in the terminal so the agent sees the target
type_in_terminal "ls -lh *.hdf"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="