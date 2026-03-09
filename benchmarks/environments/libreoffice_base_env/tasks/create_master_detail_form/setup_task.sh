#!/bin/bash
echo "=== Setting up create_master_detail_form task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Reset the database to a clean state (overwrites any previous modifications)
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file state
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="