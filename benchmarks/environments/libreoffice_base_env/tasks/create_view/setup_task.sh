#!/bin/bash
echo "=== Setting up Create View Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we start with a fresh database
echo "Restoring fresh Chinook database..."
restore_chinook_odb

# Get the initial size/checksum of the database script (to verify changes later)
# We unzip the ODB to get the internal database script
mkdir -p /tmp/initial_odb_state
unzip -p /home/ga/chinook.odb database/script > /tmp/initial_odb_state/script.original 2>/dev/null || true

# Launch LibreOffice Base
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Task: Create 'CustomerPurchaseSummary' view in chinook.odb"