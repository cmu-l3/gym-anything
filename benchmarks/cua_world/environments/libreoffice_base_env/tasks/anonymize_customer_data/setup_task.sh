#!/bin/bash
echo "=== Setting up Anonymize Customer Data Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the environment:
# 1. Kill any running LO instances
# 2. Restore fresh chinook.odb
# 3. Launch LO Base
# 4. Wait for window and dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file checksum to detect if file is modified later
md5sum /home/ga/chinook.odb > /tmp/initial_odb_checksum.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="