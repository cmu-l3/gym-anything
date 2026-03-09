#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_email_notifications task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
record_start_time "configure_email_notifications"

# Create the output directory for the evidence screenshot
# This maps to C:\LobbyTrack in Wine
mkdir -p /home/ga/.wine/drive_c/LobbyTrack
chown ga:ga /home/ga/.wine/drive_c/LobbyTrack

# Ensure clean state (optional: back up config if we were advanced, 
# but simply ensuring app is running is sufficient for this task)
echo "Ensuring Lobby Track is running..."
launch_lobbytrack

# Record initial file states for difference detection later
# We look for config files that might change
find /home/ga/.wine/drive_c/ -name "*.config" -o -name "*.xml" -o -name "*.ini" 2>/dev/null > /tmp/initial_config_files.txt

echo "=== Task setup complete ==="