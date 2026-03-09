#!/bin/bash
set -e
echo "=== Setting up customize_field_labels task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running and in a clean state
echo "Launching Lobby Track..."
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch application
launch_lobbytrack

# Ensure desktop directory exists for the output
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Remove any previous run artifacts
rm -f /home/ga/Desktop/escort_label_verification.png

# Create a cheat sheet file for the agent on the desktop
cat > /home/ga/Desktop/task_info.txt << EOF
SECURITY PROTOCOL UPDATE
========================
New Requirement: Change "Host" field label to "Escort".

Test Case:
Visitor: Viktor Antonov
Company: City 17 Logistics
Escort: Eli Vance
EOF
chown ga:ga /home/ga/Desktop/task_info.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="