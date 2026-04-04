#!/bin/bash
echo "=== Setting up implement_blob_storage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Downloads/guitar.jpg
rm -f /tmp/chinook_submitted.odb
rm -f /tmp/task_result.json

# Full setup: kill LO, restore ODB, launch, wait, dismiss dialogs, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="