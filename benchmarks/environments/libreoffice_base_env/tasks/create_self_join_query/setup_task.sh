#!/bin/bash
echo "=== Setting up create_self_join_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure LibreOffice is killed and we start fresh
kill_libreoffice

# Restore the clean Chinook ODB file
restore_chinook_odb

# Launch LibreOffice Base with the database
launch_libreoffice_base "/home/ga/chinook.odb"

# Wait for the window to appear
wait_for_libreoffice_base 60

# Dismiss any startup dialogs (migration, tips, etc.)
dismiss_dialogs

# Maximize the window for better visibility
maximize_libreoffice

# Capture initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="