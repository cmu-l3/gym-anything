#!/bin/bash
set -e
echo "=== Setting up generate_rating_curve task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
# This ensures no previous results exist and inputs are clean
restore_muncie_project

# 2. Setup results directory
mkdir -p /home/ga/Documents/hec_ras_results
# Clear any old results to prevent anti-gaming
rm -f /home/ga/Documents/hec_ras_results/*
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Open Terminal in Project Directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 4. Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

# 6. Display helpful info in terminal
type_in_terminal "echo '=== HEC-RAS Rating Curve Task ==='"
type_in_terminal "echo 'Project Location: $MUNCIE_DIR'"
type_in_terminal "echo 'Python libraries available: h5py, pandas, matplotlib, rashdf'"
type_in_terminal "echo 'Goal: Run simulation, find upstream XS, plot rating curve.'"
type_in_terminal "ls -lh"

echo "=== Task setup complete ==="