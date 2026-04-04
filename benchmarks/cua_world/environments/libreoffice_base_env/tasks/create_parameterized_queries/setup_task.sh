#!/bin/bash
set -e
echo "=== Setting up create_parameterized_queries task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities for LibreOffice Base
source /workspace/scripts/task_utils.sh

# 1. Kill any existing instances to ensure a clean start
kill_libreoffice

# 2. Restore a fresh copy of the Chinook database
# This ensures we don't have leftover queries from previous runs
restore_chinook_odb

# 3. Launch LibreOffice Base with the database
launch_libreoffice_base /home/ga/chinook.odb

# 4. Wait for the window to appear (timeout 45s)
if ! wait_for_libreoffice_base 45; then
    echo "WARNING: LibreOffice did not start in time, retrying once..."
    kill_libreoffice
    launch_libreoffice_base /home/ga/chinook.odb
    wait_for_libreoffice_base 60
fi

# 5. Dismiss any first-run dialogs or migration prompts
sleep 5
dismiss_dialogs

# 6. Maximize the window for better agent visibility
maximize_libreoffice

# 7. Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="