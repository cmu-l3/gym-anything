#!/bin/bash
set -e
echo "=== Setting up configure_facility_profile task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
record_start_time "configure_facility_profile"

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window to stabilize
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="