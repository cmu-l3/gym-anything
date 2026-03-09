#!/bin/bash
set -euo pipefail

echo "=== Setting up customize_log_view task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
record_start_time "customize_log_view"

# Ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Ensure realistic data is present (copied from env setup, but ensuring permissions)
# This ensures the grid isn't empty, making column verification easier
DATA_DIR="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Sample Data"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    # Fallback: copy from /workspace/data if standard path missing
    cp -r /workspace/data/* "$DATA_DIR/" 2>/dev/null || true
fi

# Launch Lobby Track
launch_lobbytrack

# Wait for the main window to settle
sleep 5

# Take initial screenshot to prove starting state (likely has default columns)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="