#!/bin/bash
set -e
echo "=== Setting up Configure Mandatory Visitor Field task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to be ready and maximize it
WID=$(wait_for_lobbytrack_window 30)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Locate the database file to monitor for changes
# Typical location in Wine prefix
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack*.sdf" -o -name "LobbyTrack*.mdb" 2>/dev/null | head -1)

if [ -n "$DB_FILE" ]; then
    echo "Monitoring database file: $DB_FILE"
    # Record initial modification time
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
    # Record initial size
    stat -c %s "$DB_FILE" > /tmp/initial_db_size.txt
else
    echo "WARNING: Database file not found for monitoring."
    echo "0" > /tmp/initial_db_mtime.txt
    echo "0" > /tmp/initial_db_size.txt
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="