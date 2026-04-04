#!/bin/bash
set -e
echo "=== Setting up create_readonly_form task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial file checksum/timestamp to detect if saved
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="