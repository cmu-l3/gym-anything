#!/bin/bash
# Setup script for dbeaver_export_task_automation
# Pre-configures the Chinook connection and cleans previous artifacts

set -e
echo "=== Setting up DBeaver Export Task Automation ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR" "$CONFIG_DIR"
chown -R ga:ga /home/ga/Documents

# Clean up previous artifacts
rm -f "$EXPORT_DIR/top_spenders.csv"
rm -f "$CONFIG_DIR/tasks.json" # Reset tasks
# Find and remove the specific SQL script if it exists anywhere
find /home/ga -name "top_customers_query.sql" -delete 2>/dev/null || true

# Pre-configure Chinook connection (inject into data-sources.json)
# This ensures the agent starts with the connection ready, focusing the task on the Automation feature.
DATA_SOURCES_FILE="$CONFIG_DIR/data-sources.json"
cat > "$DATA_SOURCES_FILE" << EOF
{
    "folders": {},
    "connections": {
        "chinook_sqlite": {
            "provider": "sqlite_jdbc",
            "driver": "sqlite_jdbc",
            "name": "Chinook",
            "save-password": true,
            "configuration": {
                "database": "${DB_PATH}",
                "url": "jdbc:sqlite:${DB_PATH}",
                "type": "dev"
            }
        }
    },
    "connection-types": {
        "dev": {
            "name": "Development",
            "color": "255,255,255",
            "description": "Regular development database",
            "auto-commit": true,
            "confirm-execute": false,
            "confirm-data-change": false,
            "auto-close-transactions": false
        }
    }
}
EOF
chown -R ga:ga "/home/ga/.local/share/DBeaverData"

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    
    # Wait for DBeaver to start
    for i in {1..60}; do
        if is_dbeaver_running; then
            echo "DBeaver started"
            break
        fi
        sleep 1
    done
    sleep 10 # Allow GUI to initialize
fi

# Focus and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="