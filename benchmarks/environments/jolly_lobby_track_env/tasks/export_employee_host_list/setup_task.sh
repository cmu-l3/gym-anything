#!/bin/bash
set -euo pipefail

echo "=== Setting up export_employee_host_list task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "export_employee_host_list"

# Clean up any previous run artifacts
rm -f /home/ga/Documents/employee_roster.csv
rm -f /home/ga/Documents/employee_roster.txt
rm -f /tmp/task_result.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing Lobby Track instance to ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
# This utility function handles waiting for the window and maximizing it
launch_lobbytrack

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Export Employee Host list to ~/Documents/employee_roster.csv"