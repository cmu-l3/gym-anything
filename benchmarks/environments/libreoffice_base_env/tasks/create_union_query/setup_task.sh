#!/bin/bash
set -e
echo "=== Setting up create_union_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record initial ODB checksum to detect if file was modified later
md5sum /home/ga/chinook.odb > /tmp/initial_odb_checksum.txt 2>/dev/null || true

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
# This ensures the agent starts with a clean state and the app focused
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial state screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== create_union_query task setup complete ==="