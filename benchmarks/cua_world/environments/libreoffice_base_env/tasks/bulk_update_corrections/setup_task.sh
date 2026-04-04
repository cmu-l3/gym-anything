#!/bin/bash
set -e
echo "=== Setting up Bulk Update Corrections Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Reset LibreOffice and Database
# This function (from task_utils.sh) handles killing LO, restoring chinook.odb,
# launching LO, waiting for window, dismissing dialogs, and maximizing.
setup_libreoffice_base_task /home/ga/chinook.odb

# 2. Record Initial State Evidence
# Capture the initial screenshot showing the app is open
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Record initial file timestamp
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="