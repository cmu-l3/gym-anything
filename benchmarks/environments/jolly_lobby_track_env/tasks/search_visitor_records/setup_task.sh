#!/bin/bash
echo "=== Setting up search_visitor_records task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "search_visitor_records"

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

# Create a note about the search task
cat > /home/ga/LobbyTrack/search_instructions.txt << 'EOF'
Search Task Instructions:
1. Search for visitor: Richard Taylor from JPMorgan Chase
2. Find his most recent visit record
3. Note: visit date, host name, and purpose
4. Export/save a report to Desktop containing:
   - Visitor name: Richard Taylor
   - Company: JPMorgan Chase
   - Visit date(s)
   - Host(s) visited
   - Purpose of visit(s)

Save the report to: Desktop/taylor_report.txt
EOF
chown ga:ga /home/ga/LobbyTrack/search_instructions.txt

# Launch Lobby Track
launch_lobbytrack

echo "=== search_visitor_records task setup complete ==="
echo "Task: Search for Richard Taylor from JPMorgan Chase and export visit report"
