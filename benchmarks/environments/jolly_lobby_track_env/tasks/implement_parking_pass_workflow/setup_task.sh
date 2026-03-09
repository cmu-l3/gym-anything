#!/bin/bash
set -e
echo "=== Setting up Parking Pass Workflow Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time

# Ensure Lobby Track is not running initially to ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 2

# Remove any pre-existing "Parking Permit" templates to ensure fresh creation
find /home/ga/.wine/drive_c -name "Parking Permit*" -delete 2>/dev/null || true

# Launch Lobby Track
launch_lobbytrack

# Record initial state of database files (to detect modifications)
# Lobby Track usually keeps data in ProgramData or Public Documents
echo "Recording initial file states..."
find /home/ga/.wine/drive_c -name "*.sdf" -o -name "*.mdb" -o -name "*.xml" > /tmp/initial_files.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="