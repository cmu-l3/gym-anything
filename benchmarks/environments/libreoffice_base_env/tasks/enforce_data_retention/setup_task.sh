#!/bin/bash
echo "=== Setting up enforce_data_retention task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial file state
if [ -f /home/ga/chinook.odb ]; then
    stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
    stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt
fi

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="