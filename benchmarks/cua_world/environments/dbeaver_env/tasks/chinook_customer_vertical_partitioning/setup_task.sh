#!/bin/bash
# Setup script for chinook_customer_vertical_partitioning task

echo "=== Setting up Vertical Partitioning Task ==="

source /workspace/scripts/task_utils.sh

# Paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_refactor.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist and are clean
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
rm -f "$EXPORT_DIR/refactored_customers.csv"
rm -f "$SCRIPTS_DIR/partitioning.sql"

# Prepare the database
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source Chinook database not found!"
    # Fallback to creating it if missing (should be handled by env setup, but safe to have)
    wget -q -O /tmp/chinook.db "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    mv /tmp/chinook.db "$SOURCE_DB"
fi

echo "Creating working database copy..."
cp "$SOURCE_DB" "$TARGET_DB"
chown ga:ga "$TARGET_DB"

# Verify initial state
INITIAL_ROWS=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers;")
echo "Initial customer rows: $INITIAL_ROWS"
echo "$INITIAL_ROWS" > /tmp/initial_row_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Start DBeaver
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="