#!/bin/bash
echo "=== Setting up analyze_customer_tenure task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file state
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="