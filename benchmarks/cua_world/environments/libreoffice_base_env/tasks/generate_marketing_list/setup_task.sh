#!/bin/bash
echo "=== Setting up generate_marketing_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/mailing_list.csv
rm -f /tmp/task_result.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
# Using the standard chinook.odb
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="