#!/bin/bash
echo "=== Setting up register_walkin_visitor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "register_walkin_visitor"

# Kill any existing Lobby Track instance
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Copy visitor data to accessible location
mkdir -p /home/ga/LobbyTrack/data
cp /workspace/data/visitor_records.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
cp /workspace/data/employee_hosts.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/LobbyTrack/

# Launch Lobby Track (waits for window to appear)
launch_lobbytrack

echo "=== register_walkin_visitor task setup complete ==="
echo "Task: Register walk-in visitor Maria Hernandez from Deloitte LLP"
