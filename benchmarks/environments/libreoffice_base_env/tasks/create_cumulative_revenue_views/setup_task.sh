#!/bin/bash
echo "=== Setting up Create Cumulative Revenue Views Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Reset the database to a clean state
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
INITIAL_MTIME=$(stat -c %Y /home/ga/chinook.odb 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="
echo "LibreOffice Base is ready."
echo "Task: Create 'MonthlyRevenue' and 'CumulativeRevenue' views."