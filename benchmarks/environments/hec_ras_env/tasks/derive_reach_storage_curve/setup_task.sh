#!/bin/bash
echo "=== Setting up derive_reach_storage_curve task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure output directory exists and is empty
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/*.csv
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 5. Display geometry file info to helper the agent start
type_in_terminal "ls -lh *.hdf"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="