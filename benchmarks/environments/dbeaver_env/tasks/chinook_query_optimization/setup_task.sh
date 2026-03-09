#!/bin/bash
# Setup script for chinook_query_optimization task

set -e
echo "=== Setting up Chinook Query Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
CHINOOK_SRC="/home/ga/Documents/databases/chinook.db"
CHINOOK_PERF="/home/ga/Documents/databases/chinook_perf.db"
SCRIPTS_DIR="/home/ga/Documents/scripts"
EXPORTS_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$SCRIPTS_DIR" "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents

# Prepare the performance database
if [ -f "$CHINOOK_SRC" ]; then
    echo "Creating performance database copy..."
    cp "$CHINOOK_SRC" "$CHINOOK_PERF"
else
    echo "ERROR: Source database not found!"
    exit 1
fi

# Ensure no indexes exist on the target columns (to prevent pre-solved state)
# We use sqlite3 to drop them if they exist (Chinook standard doesn't have them, but safety first)
echo "Ensuring clean state for indexes..."
sqlite3 "$CHINOOK_PERF" <<EOF
DROP INDEX IF EXISTS IFK_InvoiceDate;
DROP INDEX IF EXISTS IFK_CustomerCity;
DROP INDEX IF EXISTS IFK_TrackComposer;
DROP INDEX IF EXISTS IFK_TrackMilliseconds;
EOF

chown ga:ga "$CHINOOK_PERF"

# Record initial state
date +%s > /tmp/task_start_time

# Record number of indexes initially
INITIAL_INDEX_COUNT=$(sqlite3 "$CHINOOK_PERF" "SELECT count(*) FROM sqlite_master WHERE type='index';")
echo "$INITIAL_INDEX_COUNT" > /tmp/initial_index_count

# Clear output files if they exist
rm -f "$SCRIPTS_DIR/create_indexes.sql"
rm -f "$EXPORTS_DIR/optimization_report.csv"

# Start DBeaver
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
    sleep 5
fi

# Maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="