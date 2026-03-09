#!/bin/bash
echo "=== Setting up analyze_storage_usage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="