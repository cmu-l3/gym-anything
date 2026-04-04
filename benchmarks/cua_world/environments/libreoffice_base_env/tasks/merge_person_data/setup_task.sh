#!/bin/bash
set -e
echo "=== Setting up merge_person_data task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Reset the database to a clean state
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file state
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="