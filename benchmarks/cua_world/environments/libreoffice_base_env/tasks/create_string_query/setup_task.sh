#!/bin/bash
echo "=== Setting up Create String Query Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial size/time of the database file
ODB_PATH="/home/ga/chinook.odb"
if [ -f "$ODB_PATH" ]; then
    stat -c %Y "$ODB_PATH" > /tmp/initial_odb_mtime.txt
    stat -c %s "$ODB_PATH" > /tmp/initial_odb_size.txt
else
    echo "0" > /tmp/initial_odb_mtime.txt
    echo "0" > /tmp/initial_odb_size.txt
fi

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task "$ODB_PATH"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="