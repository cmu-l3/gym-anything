#!/bin/bash
echo "=== Setting up Configure Contractor Group Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "configure_contractor_group"

# Ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Record initial state of database files (timestamps and content)
# We want to detect if the database actually changes
echo "Recording initial database state..."
find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" -o -name "*.xml" 2>/dev/null | while read db_file; do
    md5sum "$db_file" >> /tmp/initial_db_hashes.txt 2>/dev/null || true
done

# Launch Lobby Track
# This function (from task_utils.sh) handles waiting for the window and maximizing it
launch_lobbytrack

# Take initial screenshot for VLM baseline
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Task: Rename 'Members' group to 'Contractors' and show on Main Menu"