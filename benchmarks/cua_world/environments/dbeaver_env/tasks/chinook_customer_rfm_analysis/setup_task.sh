#!/bin/bash
echo "=== Setting up Chinook RFM Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Configuration
CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous artifacts
rm -f "$EXPORT_DIR/rfm_segments.csv"
rm -f "$SCRIPTS_DIR/rfm_analysis.sql"

# Clean up database state (drop customer_rfm if it exists from previous run)
if [ -f "$CHINOOK_DB" ]; then
    echo "Cleaning up database..."
    sqlite3 "$CHINOOK_DB" "DROP TABLE IF EXISTS customer_rfm;" 2>/dev/null || true
    sqlite3 "$CHINOOK_DB" "DROP VIEW IF EXISTS customer_rfm;" 2>/dev/null || true
else
    echo "ERROR: Chinook database not found at $CHINOOK_DB"
    exit 1
fi

# Record task start time
date +%s > /tmp/task_start_time

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            echo "DBeaver started"
            break
        fi
        sleep 1
    done
fi

# Focus DBeaver
focus_dbeaver
sleep 2

# Maximize window
WID=$(get_dbeaver_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/rfm_initial.png

echo "=== Setup Complete ==="