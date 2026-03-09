#!/bin/bash
set -e
echo "=== Setting up create_indexes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running LibreOffice instances
kill_libreoffice

# Restore a fresh copy of the Chinook database
restore_chinook_odb

# Launch LibreOffice Base with the database
launch_libreoffice_base /home/ga/chinook.odb

# Wait for window to appear
wait_for_libreoffice_base 45

# Allow UI to render
sleep 3

# Dismiss any startup dialogs (e.g., first run, migration)
dismiss_dialogs

# Maximize the window for visibility
maximize_libreoffice

# Record initial file state for verification
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="