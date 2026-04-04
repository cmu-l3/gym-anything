#!/bin/bash
echo "=== Setting up Chinook Royalty Calculation Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and have correct permissions
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents

# Ensure clean state in database
# We remove the target tables if they exist from a previous run to force the agent to create them
if [ -f "$DB_PATH" ]; then
    echo "Cleaning up previous task artifacts from database..."
    sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS artist_monthly_royalties;"
    sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS royalty_rates;"
else
    echo "ERROR: Chinook database not found at $DB_PATH"
    # Try to copy from backup/source if available (handled by general setup, but good safeguard)
    if [ -f "/workspace/data/chinook.db" ]; then
        cp /workspace/data/chinook.db "$DB_PATH"
    fi
fi

# Remove files
rm -f "$EXPORT_DIR/royalty_summary.csv"
rm -f "$SCRIPTS_DIR/royalty_calculation.sql"

# Ensure DBeaver is running
if ! pgrep -f "dbeaver" > /dev/null; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for DBeaver to start
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            echo "DBeaver window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus DBeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_dbeaver 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="