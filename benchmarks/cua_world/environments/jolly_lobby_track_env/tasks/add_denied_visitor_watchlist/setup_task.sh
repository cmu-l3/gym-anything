#!/bin/bash
set -e
echo "=== Setting up Watchlist Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Start Time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 2. Setup/Clean State
# Ensure Lobby Track is not running initially to allow clean DB state recording
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# 3. Snapshot Database State
# We identify the database file (usually .mdb or .sdf in ProgramData or Common AppData)
# If exact path is unknown, we record the state of the likely data directory
DATA_DIR="/home/ga/.wine/drive_c/ProgramData/Jolly Technologies"
if [ -d "$DATA_DIR" ]; then
    find "$DATA_DIR" -type f -name "*.mdb" -o -name "*.sdf" -o -name "*.db" | xargs ls -l --time-style=+%s > /tmp/initial_db_state.txt 2>/dev/null || true
else
    echo "Warning: Data directory not found at $DATA_DIR" > /tmp/initial_db_state.txt
fi

# 4. Launch Application
launch_lobbytrack

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="