#!/bin/bash
echo "=== Setting up compute_riprap_sizing task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
# This ensures inputs are valid but wipes previous results
restore_muncie_project

# 2. Force the agent to run the simulation:
# Remove any existing result files to verify the agent can run the simulation
rm -f "$MUNCIE_DIR"/*.p04.hdf
rm -f "$MUNCIE_DIR"/*.p04.tmp.hdf
rm -f "/home/ga/Documents/hec_ras_results/riprap_design.csv"
rm -f "/home/ga/Documents/hec_ras_results/riprap_summary.txt"

# 3. Create results directory
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type 'ls' to show files
type_in_terminal "ls -lh"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="