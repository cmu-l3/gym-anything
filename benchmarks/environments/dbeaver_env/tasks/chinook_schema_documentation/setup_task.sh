#!/bin/bash
# Setup script for chinook_schema_documentation
# Ensures DBeaver is running and environment is clean

echo "=== Setting up Chinook Schema Documentation Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"

# 2. Clean previous artifacts
rm -f "$EXPORT_DIR/chinook_schema.sql"
rm -f "$EXPORT_DIR/chinook_relationships.csv"
rm -f "$EXPORT_DIR/chinook_table_stats.csv"
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"

# 3. Ensure database exists
if [ ! -f "$DB_PATH" ]; then
    echo "Restoring Chinook database..."
    /workspace/scripts/setup_dbeaver.sh
fi

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time

# 5. Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "dbeaver"; then
            echo "DBeaver window detected"
            break
        fi
        sleep 1
    done
fi

# 6. Maximize and focus DBeaver
focus_dbeaver
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="