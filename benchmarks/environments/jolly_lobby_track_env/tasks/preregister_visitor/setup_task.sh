#!/bin/bash
echo "=== Setting up preregister_visitor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "preregister_visitor"

# Kill any existing Lobby Track instance
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Copy data files
mkdir -p /home/ga/LobbyTrack/data
cp /workspace/data/visitor_records.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
cp /workspace/data/employee_hosts.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/LobbyTrack/

# Create a note for the agent about tomorrow's date
TOMORROW=$(date -d "+1 day" +"%Y-%m-%d")
echo "Scheduled visit date: $TOMORROW at 2:00 PM" > /home/ga/LobbyTrack/scheduled_visit_info.txt
echo "Visitor: Robert Johnson, Microsoft Corporation" >> /home/ga/LobbyTrack/scheduled_visit_info.txt
echo "Host: James Wilson, Engineering" >> /home/ga/LobbyTrack/scheduled_visit_info.txt
chown ga:ga /home/ga/LobbyTrack/scheduled_visit_info.txt

# Launch Lobby Track
launch_lobbytrack

echo "=== preregister_visitor task setup complete ==="
echo "Task: Pre-register Robert Johnson from Microsoft for $TOMORROW at 2:00 PM"
