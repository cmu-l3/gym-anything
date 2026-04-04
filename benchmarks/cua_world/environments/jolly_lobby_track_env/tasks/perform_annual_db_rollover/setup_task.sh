#!/bin/bash
set -euo pipefail

echo "=== Setting up Perform Annual Database Rollover task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "perform_annual_db_rollover"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
# Clean up any previous run artifacts
rm -f /home/ga/Documents/VisitorLog_2025_Archive* 2>/dev/null || true
rm -f /home/ga/Documents/verification_empty_log.csv 2>/dev/null || true

# Kill any existing Lobby Track instance
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Reset Database State:
# We need to ensure there is data to backup and purge.
# Copying sample data to the active Lobby Track data location.
# Note: The specific location depends on installation, but we target the standard Wine paths.

DATA_SRC="/workspace/data/sample_db" # Assuming this exists from env setup or we use the installed sample
LOBBY_TRACK_DATA_DIR="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Sample Data"
USER_DB_DIR="/home/ga/LobbyTrack/data"

# Ensure user data dir exists
mkdir -p "$USER_DB_DIR"

# If environment has a sample database restoration script or file, use it.
# Otherwise, we rely on the default sample data being present.
if [ -d "$DATA_SRC" ]; then
    echo "Restoring sample data from $DATA_SRC..."
    cp -r "$DATA_SRC/"* "$USER_DB_DIR/" 2>/dev/null || true
fi

# Launch Lobby Track
launch_lobbytrack

# Record initial file system state of the data directory (to compare later if needed)
find "$USER_DB_DIR" -type f -exec ls -l {} \; > /tmp/initial_data_state.txt 2>/dev/null || true

echo "=== perform_annual_db_rollover task setup complete ==="
echo "Instructions:"
echo "1. Backup current data to ~/Documents/VisitorLog_2025_Archive"
echo "2. Purge/Delete ALL visitor log records (keep Hosts)"
echo "3. Export empty log to ~/Documents/verification_empty_log.csv"