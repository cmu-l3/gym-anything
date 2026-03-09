#!/bin/bash
set -e
echo "=== Setting up Reconstruct Playlist Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial file timestamp
if [ -f /home/ga/chinook.odb ]; then
    stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt
else
    echo "0" > /tmp/initial_odb_mtime.txt
fi

# Standard setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="