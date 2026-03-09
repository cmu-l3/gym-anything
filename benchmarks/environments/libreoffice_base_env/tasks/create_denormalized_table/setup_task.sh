#!/bin/bash
set -e
echo "=== Setting up create_denormalized_table task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Restore a fresh copy of the Chinook database
# This ensures we start with a known clean state
restore_chinook_odb

# Calculate initial checksum of the ODB file to detect changes later
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_md5.txt

# Launch LibreOffice Base
launch_libreoffice_base "/home/ga/chinook.odb"

# Wait for window to appear (up to 45s)
wait_for_libreoffice_base 45

# Allow UI to render
sleep 3

# Dismiss any startup dialogs (migration, tips, etc.)
dismiss_dialogs

# Maximize the window for better agent visibility
maximize_libreoffice

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="