#!/bin/bash
echo "=== Setting up vendor_department_access_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "vendor_department_access_report"

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
rm -f /home/ga/Desktop/vendor_dept_access_dec2025.csv

# Record baseline
INITIAL_DESKTOP_CSVS=$(ls /home/ga/Desktop/*.csv 2>/dev/null | wc -l)
echo "$INITIAL_DESKTOP_CSVS" > /tmp/vendor_dept_initial_desktop_count

# Take initial screenshot
take_screenshot "vendor_department_access_report_start"

# Launch Lobby Track
launch_lobbytrack

echo "=== vendor_department_access_report setup complete ==="
echo "Task: Analyze December 2025 vendor visits by department and export summary"
echo "Output expected at: /home/ga/Desktop/vendor_dept_access_dec2025.csv"
