#!/bin/bash
# Setup script for chinook_cohort_retention
# Ensures DBeaver is running and environment is clean

set -e
echo "=== Setting up Chinook Cohort Retention Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Clean previous artifacts
rm -f "$EXPORT_DIR/cohort_retention.csv"
rm -f "$EXPORT_DIR/cohort_summary.txt"
rm -f "$SCRIPTS_DIR/cohort_analysis.sql"

# Verify database exists
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Attempt to restore from backup or copy from source if setup_dbeaver failed
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$DB_PATH"
    else
        echo "CRITICAL: Cannot find chinook.db"
        exit 1
    fi
fi
chown ga:ga "$DB_PATH"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            echo "DBeaver started."
            break
        fi
        sleep 1
    done
fi

# Focus DBeaver
focus_dbeaver || true
sleep 2

# Maximize window
WID=$(get_dbeaver_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="