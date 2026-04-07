#!/bin/bash
echo "=== Setting up generate_sprint_csv_export task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is reachable
wait_for_openproject

# Clean up any previous attempts or stale files
rm -f /home/ga/Documents/sprint1_export.csv
rm -f /home/ga/Downloads/*.csv
rm -f /home/ga/Downloads/*.xls
# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch Firefox to the project's work package list
# This gives the agent a helpful starting point but doesn't do the work
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 8

# Maximize Firefox for better visibility
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Export Sprint 1 WPs to /home/ga/Documents/sprint1_export.csv"