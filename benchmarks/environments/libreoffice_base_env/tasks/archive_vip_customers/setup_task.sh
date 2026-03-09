#!/bin/bash
set -e
echo "=== Setting up archive_vip_customers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
# This ensures a clean state with chinook.odb loaded
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
STAT_CMD="stat -c %Y /home/ga/chinook.odb"
INITIAL_MTIME=$($STAT_CMD 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_odb_mtime.txt

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Goal: Create 'GalaInvitees' table with top 15 spending customers."