#!/bin/bash
# Setup for transfer_region_accounts task
set -e

echo "=== Setting up transfer_region_accounts task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure we start with a clean state (kill LO, restore clean ODB)
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Create 'TransferLog' table (CustomerId, OldRepId, NewRepId, TransferDate)"
echo "2. Find customers in USA/Canada assigned to Jane Peacock (ID 3)"
echo "3. Log them in TransferLog (NewRepId = 4)"
echo "4. Update their SupportRepId to 4"