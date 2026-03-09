#!/bin/bash
# Pre-task setup for split_invoice_items

echo "=== Setting up Split Invoice Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the database to a fresh state
echo "Restoring fresh Chinook database..."
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp for change detection
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="