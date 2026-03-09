#!/bin/bash
echo "=== Setting up populate_curated_playlist task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="