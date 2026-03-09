#!/bin/bash
# Setup script for chinook_audio_audit
# Prepares clean state and records timestamps

echo "=== Setting up Chinook Audio Audit Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Database path
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR"
mkdir -p "$SCRIPTS_DIR"

# Clean up any previous run artifacts
rm -f "$EXPORT_DIR/hifi_candidates.csv"
rm -f "$SCRIPTS_DIR/genre_quality.sql"

# Clean up database state (remove view if exists from previous run)
if [ -f "$DB_PATH" ]; then
    echo "Cleaning up database views..."
    sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_track_bitrates;"
else
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Try to copy from backup if setup_dbeaver.sh failed
    if [ -f "/workspace/data/chinook.db" ]; then
        cp /workspace/data/chinook.db "$DB_PATH"
    fi
fi

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="