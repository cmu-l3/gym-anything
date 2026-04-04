#!/bin/bash
echo "=== Setting up locate_database_file task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "locate_database_file"

# Remove any previous report
rm -f /home/ga/lobby_track_db_report.txt

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait a moment for window to stabilize
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="