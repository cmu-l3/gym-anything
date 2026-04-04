#!/bin/bash
set -e
echo "=== Setting up create_summary_table task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial ODB file hash to detect "do nothing"
md5sum /home/ga/chinook.odb 2>/dev/null | awk '{print $1}' > /tmp/initial_odb_hash.txt || echo "0" > /tmp/initial_odb_hash.txt

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
# This ensures the agent starts with a clean state and the app is ready
setup_libreoffice_base_task /home/ga/chinook.odb

# Take screenshot of initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="