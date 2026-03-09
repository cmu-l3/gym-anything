#!/bin/bash
set -euo pipefail

echo "=== Setting up assign_group_badge_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
record_start_time "assign_group_badge_template"

# Ensure clean state by killing existing instances
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack

# Wait for window to stabilize
sleep 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

# Record initial database state (timestamp)
# Find the main database file - typically standard.mdb or similar in the installation or public docs
DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | head -n 1)
if [ -f "$DB_FILE" ]; then
    STAT_CMD=$(stat -c %Y "$DB_FILE")
    echo "$STAT_CMD" > /tmp/initial_db_mtime.txt
    echo "Located database file: $DB_FILE"
else
    echo "0" > /tmp/initial_db_mtime.txt
    echo "WARNING: Could not locate database file for tracking"
fi

echo "=== Task setup complete ==="