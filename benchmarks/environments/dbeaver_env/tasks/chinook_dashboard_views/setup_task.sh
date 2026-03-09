#!/bin/bash
# Setup script for chinook_dashboard_views
# Prepares the environment and records initial state

set -e
echo "=== Setting up Chinook Dashboard Views Task ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR"
mkdir -p "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# 1. Ensure Chinook database exists and is clean
if [ ! -f "$DB_PATH" ]; then
    echo "Restoring Chinook database..."
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$DB_PATH"
    else
        # Fallback download if not in workspace data
        wget -q -O "$DB_PATH" "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    fi
fi
chown ga:ga "$DB_PATH"

# 2. Drop target views if they already exist (to ensure fresh creation)
echo "Cleaning up any existing views..."
sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_customer_spending;"
sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_genre_revenue;"
sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_employee_sales_summary;"

# 3. Remove output files
rm -f "$EXPORT_DIR/customer_spending.csv"
rm -f "$EXPORT_DIR/genre_revenue.csv"
rm -f "$EXPORT_DIR/employee_sales.csv"
rm -f "$SCRIPTS_DIR/dashboard_views.sql"

# 4. Record initial state for verifier
# Check connection count
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(grep -c '"id"' "$DBEAVER_CONFIG" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_conn_count

# Record Task Start Time
date +%s > /tmp/task_start_time

# 5. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "DBeaver"; then
            break
        fi
        sleep 1
    done
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="