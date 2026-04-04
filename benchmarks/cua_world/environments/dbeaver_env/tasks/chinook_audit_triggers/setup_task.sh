#!/bin/bash
# Setup script for chinook_audit_triggers task

set -e
echo "=== Setting up Chinook Audit Triggers Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_triggers.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up any previous run artifacts
rm -f "$EXPORT_DIR/audit_log.csv"
rm -f "$SCRIPTS_DIR/audit_triggers.sql"

# Prepare the specific database copy for this task
if [ -f "$SOURCE_DB" ]; then
    echo "Creating fresh copy of Chinook database..."
    cp "$SOURCE_DB" "$TARGET_DB"
    chown ga:ga "$TARGET_DB"
    chmod 644 "$TARGET_DB"
else
    echo "ERROR: Source Chinook database not found at $SOURCE_DB"
    exit 1
fi

# Record initial database state (should be 0 triggers)
INITIAL_TRIGGER_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'" 2>/dev/null || echo "0")
echo "$INITIAL_TRIGGER_COUNT" > /tmp/initial_trigger_count.txt
echo "Initial trigger count: $INITIAL_TRIGGER_COUNT"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for DBeaver to start
    for i in {1..30}; do
        if is_dbeaver_running; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Focus and maximize DBeaver
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="