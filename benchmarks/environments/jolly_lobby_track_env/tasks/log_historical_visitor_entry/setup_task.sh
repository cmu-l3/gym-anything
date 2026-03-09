#!/bin/bash
set -e
echo "=== Setting up log_historical_visitor_entry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "log_historical_visitor_entry"

# Calculate 'Yesterday' for verification purposes
# We store it in a file so the export script/verifier knows what the 'correct' date was relative to the task start
# Format: MM/DD/YYYY and YYYY-MM-DD for easier matching
date -d "yesterday" +%m/%d/%Y > /tmp/target_date_us.txt
date -d "yesterday" +%Y-%m-%d > /tmp/target_date_iso.txt
echo "Target Date (Yesterday): $(cat /tmp/target_date_us.txt)"

# Kill any existing Lobby Track instance to ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Launch Lobby Track
launch_lobbytrack

# Ensure clean slate for the export file
rm -f /home/ga/Documents/verification_export.* 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target Date: Yesterday"