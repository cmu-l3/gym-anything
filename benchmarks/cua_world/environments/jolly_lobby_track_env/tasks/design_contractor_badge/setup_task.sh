#!/bin/bash
set -e
echo "=== Setting up design_contractor_badge task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "design_contractor_badge"

# Kill any existing Lobby Track instance to ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Cleanup: Remove any existing files that match the target name to prevent false positives
echo "Cleaning up previous run artifacts..."
find /home/ga -name "Contractor_Badge.*" -delete 2>/dev/null || true

# Ensure standard template directories exist (so save dialog defaults somewhere valid)
mkdir -p "/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Templates/Badges" 2>/dev/null || true
mkdir -p "/home/ga/.wine/drive_c/users/Public/Documents/Jolly Technologies/Lobby Track/Templates" 2>/dev/null || true

# Launch Lobby Track
launch_lobbytrack

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="