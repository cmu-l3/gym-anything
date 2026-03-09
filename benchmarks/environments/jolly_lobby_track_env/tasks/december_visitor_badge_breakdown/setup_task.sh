#!/bin/bash
echo "=== Setting up december_visitor_badge_breakdown task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "december_visitor_badge_breakdown"

# Kill any existing Lobby Track instance
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Copy data files to LobbyTrack data directory
mkdir -p /home/ga/LobbyTrack/data
cp /workspace/data/visitor_records.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
cp /workspace/data/employee_hosts.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/LobbyTrack/

# Remove any pre-existing output file to ensure clean state
rm -f /home/ga/Desktop/dec2025_visitor_analysis.csv

# Record baseline
INITIAL_DESKTOP_CSVS=$(ls /home/ga/Desktop/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_DESKTOP_CSVS" > /tmp/dec_badge_initial_desktop_count

# Take initial screenshot
take_screenshot "december_visitor_badge_breakdown_start"

# Launch Lobby Track
launch_lobbytrack

echo "=== december_visitor_badge_breakdown setup complete ==="
echo "Task: Generate December 2025 visitor analysis with badge type breakdown and top departments"
echo "Output expected at: /home/ga/Desktop/dec2025_visitor_analysis.csv"
