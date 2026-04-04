#!/bin/bash
echo "=== Setting up generate_visitor_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "generate_visitor_report"

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

# Create report generation instructions
cat > /home/ga/LobbyTrack/report_instructions.txt << 'EOF'
Report Generation Task Instructions:
1. Navigate to the Reports section of Lobby Track
2. Set date range: December 1, 2025 to December 31, 2025
3. Generate a comprehensive visitor report
4. The report should include:
   - All visitors who signed in during December 2025
   - Visitor names, companies, hosts visited
   - Dates and sign-in/sign-out times
5. Export/save the report to the Desktop

Expected: ~40 visitor records from December 2025
EOF
chown ga:ga /home/ga/LobbyTrack/report_instructions.txt

# Launch Lobby Track
launch_lobbytrack

echo "=== generate_visitor_report task setup complete ==="
echo "Task: Generate December 2025 visitor report and export to Desktop"
