#!/bin/bash
set -e
echo "=== Setting up register_visitor_with_credential task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /home/ga/Documents/security_checkin.csv 2>/dev/null || true
rm -f /home/ga/Documents/*.csv 2>/dev/null || true

# Kill any existing Lobby Track instance to ensure fresh start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Ensure Documents directory exists (for agent to save to)
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch Lobby Track
# This utility function (from task_utils.sh) handles the Wine launch, 
# waits for the window, maximizes it, and dismisses startup dialogs.
launch_lobbytrack

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="