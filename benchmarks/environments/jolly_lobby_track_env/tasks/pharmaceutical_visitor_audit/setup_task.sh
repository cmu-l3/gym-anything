#!/bin/bash
echo "=== Setting up pharmaceutical_visitor_audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "pharmaceutical_visitor_audit"

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
rm -f /home/ga/Desktop/pharma_healthcare_visitor_audit.csv

# Record baseline
INITIAL_DESKTOP_CSVS=$(ls /home/ga/Desktop/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_DESKTOP_CSVS" > /tmp/pharma_audit_initial_desktop_count

# Take initial screenshot
take_screenshot "pharmaceutical_visitor_audit_start"

# Launch Lobby Track
launch_lobbytrack

echo "=== pharmaceutical_visitor_audit setup complete ==="
echo "Task: Find pharma/healthcare company visitors in December 2025 and export audit report"
echo "Output expected at: /home/ga/Desktop/pharma_healthcare_visitor_audit.csv"
