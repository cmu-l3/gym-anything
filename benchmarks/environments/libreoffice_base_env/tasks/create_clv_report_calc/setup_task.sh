#!/bin/bash
set -e
echo "=== Setting up create_clv_report_calc task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and is clean of target file
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/CLV_Report.ods
rm -f /home/ga/Documents/CLV_Report.csv

# Clean up any stray LibreOffice processes
kill_libreoffice

# Restore fresh database to ensure known state
restore_chinook_odb

# Launch LibreOffice Base
launch_libreoffice_base /home/ga/chinook.odb

# Wait for window and handle dialogs
wait_for_libreoffice_base 45
sleep 2
dismiss_dialogs
maximize_libreoffice

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="