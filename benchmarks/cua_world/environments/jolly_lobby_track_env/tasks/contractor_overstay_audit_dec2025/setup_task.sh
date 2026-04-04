#!/bin/bash
echo "=== Setting up contractor_overstay_audit_dec2025 task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "contractor_overstay_audit_dec2025"

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
rm -f /home/ga/Desktop/contractor_overstay_dec2025.csv

# Record baseline: count of CSV files on Desktop (to detect new exports)
INITIAL_DESKTOP_CSVS=$(ls /home/ga/Desktop/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_DESKTOP_CSVS" > /tmp/contractor_overstay_initial_desktop_count

# Take initial screenshot
take_screenshot "contractor_overstay_audit_dec2025_start"

# Launch Lobby Track
launch_lobbytrack

echo "=== contractor_overstay_audit_dec2025 setup complete ==="
echo "Task: Identify contractors who stayed >2 hours in December 2025 and export compliance report"
echo "Output expected at: /home/ga/Desktop/contractor_overstay_dec2025.csv"
