#!/bin/bash
set -e
echo "=== Setting up generate_flood_warning_json task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Agent needs input data)
# This uses the utility function to run RasUnsteady if .p04.hdf is missing
run_simulation_if_needed

# 3. Clean up any previous results
rm -f /home/ga/Documents/hec_ras_results/dashboard_feed.json
mkdir -p /home/ga/Documents/hec_ras_results

# 4. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 5. Pre-load a helpful hint in the terminal history (optional but realistic)
# or just list the files so the agent sees them immediately
type_in_terminal "ls -lh *.hdf"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="