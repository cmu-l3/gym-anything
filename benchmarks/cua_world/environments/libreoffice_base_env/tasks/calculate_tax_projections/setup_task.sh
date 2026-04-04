#!/bin/bash
echo "=== Setting up calculate_tax_projections task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state: kill any running instances and restore fresh database
echo "Restoring database..."
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
if [ -f "/home/ga/chinook.odb" ]; then
    stat -c %Y "/home/ga/chinook.odb" > /tmp/initial_odb_mtime.txt
    stat -c %s "/home/ga/chinook.odb" > /tmp/initial_odb_size.txt
else
    echo "0" > /tmp/initial_odb_mtime.txt
    echo "0" > /tmp/initial_odb_size.txt
fi

# Take initial screenshot of the application ready
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Create 'NorthAmericaTaxImpact' query with 6.5% tax calculation for USA/Canada."