#!/bin/bash
set -e
echo "=== Setting up Normalize Address Table Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing LibreOffice instances
kill_libreoffice

# 2. Restore a fresh copy of the database to user home
# This ensures we start with a clean state (no CustomerAddress table)
restore_chinook_odb

# 3. Launch LibreOffice Base with the database
launch_libreoffice_base "/home/ga/chinook.odb"

# 4. Wait for window to appear
wait_for_libreoffice_base 45

# 5. Dismiss any first-run or migration dialogs
dismiss_dialogs

# 6. Maximize the window for visibility
maximize_libreoffice

# 7. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="