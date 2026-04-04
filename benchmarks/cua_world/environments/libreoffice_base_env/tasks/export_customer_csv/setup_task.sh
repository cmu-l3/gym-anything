#!/bin/bash
echo "=== Setting up Export Customer CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure the output directory exists
mkdir -p /home/ga/Documents

# Remove any pre-existing output file to ensure clean state
rm -f /home/ga/Documents/customer_spending.csv

# Launch LibreOffice Base with the Chinook database
# This handles killing old instances, restoring ODB, launching, and dismissing dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Create /home/ga/Documents/customer_spending.csv"