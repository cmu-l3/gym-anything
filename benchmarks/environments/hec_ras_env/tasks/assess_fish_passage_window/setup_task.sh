#!/bin/bash
echo "=== Setting up assess_fish_passage_window task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Prepare directories
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Open terminal in project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Pre-type a hint command to show available files (optional, helps agent orient)
type_in_terminal "ls -lh"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="