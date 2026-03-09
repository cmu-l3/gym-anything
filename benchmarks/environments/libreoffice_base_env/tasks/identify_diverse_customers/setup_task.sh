#!/bin/bash
set -e
echo "=== Setting up Identify Diverse Customers Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure we start with a fresh database
echo "Restoring fresh Chinook database..."
restore_chinook_odb

# Launch LibreOffice Base
echo "Launching LibreOffice Base..."
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="