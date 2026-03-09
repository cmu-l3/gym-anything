#!/bin/bash
echo "=== Setting up defense_sector_host_compliance task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "defense_sector_host_compliance"

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
rm -f /home/ga/Desktop/defense_host_compliance.csv

# Record baseline
INITIAL_DESKTOP_CSVS=$(ls /home/ga/Desktop/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_DESKTOP_CSVS" > /tmp/defense_compliance_initial_desktop_count

# Take initial screenshot
take_screenshot "defense_sector_host_compliance_start"

# Launch Lobby Track
launch_lobbytrack

echo "=== defense_sector_host_compliance setup complete ==="
echo "Task: Find defense/aerospace visitors with non-Security hosts and export compliance gap report"
echo "Output expected at: /home/ga/Desktop/defense_host_compliance.csv"
