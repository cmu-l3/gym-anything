#!/bin/bash
set -e
echo "=== Setting up Create Formatted Catalog View Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we start fresh
kill_libreoffice
restore_chinook_odb

# Launch LibreOffice Base with the database
launch_libreoffice_base /home/ga/chinook.odb

# Wait for the window to appear
wait_for_libreoffice_base 45

# Dismiss any startup dialogs (like "JRE Required" or "HSQLDB Migration")
sleep 5
dismiss_dialogs

# Maximize the window
maximize_libreoffice

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="