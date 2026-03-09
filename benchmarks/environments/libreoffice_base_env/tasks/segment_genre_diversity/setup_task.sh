#!/bin/bash
echo "=== Setting up segment_genre_diversity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the database to a clean state
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="