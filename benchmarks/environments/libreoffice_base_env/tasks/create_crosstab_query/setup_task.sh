#!/bin/bash
echo "=== Setting up Create Crosstab Query Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure we start with a fresh copy of the database
# This prevents previous attempts from polluting the state
kill_libreoffice
restore_chinook_odb

# Launch LibreOffice Base directly opening the database
launch_libreoffice_base /home/ga/chinook.odb

# Wait for the window to appear
if ! wait_for_libreoffice_base 45; then
    echo "ERROR: LibreOffice Base failed to launch"
    exit 1
fi

# Give it a moment to fully render
sleep 3

# Dismiss any first-run dialogs (Java, Migration, etc.)
dismiss_dialogs

# Maximize the window for better agent visibility
maximize_libreoffice

# Navigate to Queries section (optional helper, but good for starting state)
# We can't easily click specific icons without OCR, but the default view is usually Tables.
# The agent is expected to navigate.

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="