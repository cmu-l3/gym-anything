#!/bin/bash
echo "=== Setting up Create Set Operation Queries Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure a fresh copy of the database is used
# This prevents previous task artifacts from interfering
echo "Restoring fresh Chinook database..."
restore_chinook_odb

# 3. Launch LibreOffice Base
# We use the utility function to handle launch, window waiting, and maximizing
setup_libreoffice_base_task /home/ga/chinook.odb

# 4. Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Chinook database loaded."
echo "Ready for query creation."