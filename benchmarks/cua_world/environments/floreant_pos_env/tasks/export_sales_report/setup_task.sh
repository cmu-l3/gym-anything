#!/bin/bash
echo "=== Setting up export_sales_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
# Remove any existing report to ensure fresh creation
rm -f /home/ga/Desktop/sales_report.pdf

# Start Floreant POS and log in/show main screen
start_and_login

# Wait a moment for UI to settle
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Export Sales Report (PDF) to /home/ga/Desktop/sales_report.pdf"