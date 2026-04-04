#!/bin/bash
echo "=== Setting up Catalog Integrity Audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state: kill LO, restore ODB
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Perform catalog integrity audit and save results to tables in chinook.odb"