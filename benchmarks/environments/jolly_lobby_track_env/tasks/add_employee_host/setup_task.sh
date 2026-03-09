#!/bin/bash
set -e
echo "=== Setting up add_employee_host task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "add_employee_host"

# Identify the database file location for tracking
# Lobby Track usually stores data in ProgramData or the installation folder.
# We will look for .mdb (Access) or .sdf (SQL CE) files.
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | grep -i "lobby" | head -1)

if [ -n "$DB_FILE" ]; then
    echo "Found database file: $DB_FILE"
    # Record initial timestamp
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
else
    echo "WARNING: Could not locate main database file. File modification checks may be skipped."
    echo "0" > /tmp/initial_db_mtime.txt
fi

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to stabilize
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="