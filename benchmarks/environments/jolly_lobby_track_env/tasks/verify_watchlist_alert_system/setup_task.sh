#!/bin/bash
set -e
echo "=== Setting up Verify Watchlist Alert System task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running
launch_lobbytrack

# Wait for window to stabilize
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

# Clean up any previous runs
rm -f /home/ga/Documents/watchlist_alert_proof.png
rm -f /tmp/task_result.json

echo "=== Task setup complete ==="