#!/bin/bash
set -e
echo "=== Setting up analyze_customer_affinity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial file state
if [ -f /home/ga/chinook.odb ]; then
    stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
else
    echo "0" > /tmp/initial_odb_mtime.txt
fi

# Full setup: kill LO, restore ODB, launch, wait, dismiss dialogs, maximize
# We use the standard utility function which handles the complex GUI startup sequence
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="