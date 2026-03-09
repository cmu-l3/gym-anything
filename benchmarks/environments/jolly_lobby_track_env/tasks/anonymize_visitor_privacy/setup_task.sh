#!/bin/bash
set -euo pipefail

echo "=== Setting up Anonymize Visitor Privacy Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "anonymize_visitor_privacy"

# Kill any existing Lobby Track instance to ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Locate the database file if it exists and take a hash/timestamp
# We look for typical locations in Wine prefix
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -1)
if [ -n "$DB_FILE" ]; then
    echo "Found database file: $DB_FILE"
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime
else
    echo "No database file found yet (may be created on launch)"
    echo "0" > /tmp/initial_db_mtime
fi

# Launch Lobby Track (waits for window to appear)
# This uses the shared utility which handles maximizing and focusing
launch_lobbytrack

echo "=== Setup Complete ==="
echo "Task: Register 'Marcus Vane' then Anonymize the record."