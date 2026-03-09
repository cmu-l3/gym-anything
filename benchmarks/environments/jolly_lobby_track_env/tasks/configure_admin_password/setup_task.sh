#!/bin/bash
set -e
echo "=== Setting up Configure Admin Password task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. ensure Lobby Track is running
launch_lobbytrack

# 2. Wait a moment for any background file writes to settle
sleep 5

# 3. Record task start time (CRITICAL for file modification checks)
# We add a small buffer to ensure we don't catch startup file writes
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Snapshot current config state (optional, but good for debugging)
find /home/ga/.wine/drive_c/ -maxdepth 6 -name "*.xml" -o -name "*.ini" -o -name "*.config" -o -name "*.mdb" -o -name "*.sdf" > /tmp/initial_file_list.txt 2>/dev/null || true

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Set Administrator password to 'LobbySecure2024!'"