#!/bin/bash
echo "=== Setting up insert_new_artist_hierarchy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset environment to known state
# This kills any running LO instances and restores the clean chinook.odb
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file checksum/size to detect if save happened
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

echo "=== Task setup complete ==="