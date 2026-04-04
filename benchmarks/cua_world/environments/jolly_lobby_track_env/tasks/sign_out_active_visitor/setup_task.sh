#!/bin/bash
echo "=== Setting up sign_out_active_visitor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "sign_out_active_visitor"

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

# Create a note about which visitor to sign out
cat > /home/ga/LobbyTrack/signout_instructions.txt << 'EOF'
Sign Out Task Instructions:
Find and sign out the following visitor:
- Name: Patricia Williams
- Company: Pfizer Inc
- Host: Emily Davis (Procurement)
- Purpose: Vendor Meeting

She should currently appear in the active/signed-in visitors list.
After signing her out, her departure time should be recorded.
EOF
chown ga:ga /home/ga/LobbyTrack/signout_instructions.txt

# Launch Lobby Track
launch_lobbytrack

echo "=== sign_out_active_visitor task setup complete ==="
echo "Task: Sign out Patricia Williams from Pfizer Inc"
