#!/bin/bash
# Setup script for chinook_sales_data_mart task
set -e
echo "=== Setting up Chinook Sales Data Mart Task ==="

source /workspace/scripts/task_utils.sh

# define paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_dw.db"
SCRIPT_PATH="/home/ga/Documents/scripts/etl_sales_mart.sql"

# 1. Clean up any previous run artifacts
rm -f "$TARGET_DB"
rm -f "$SCRIPT_PATH"

# 2. Ensure source database exists and is valid
if [ ! -f "$SOURCE_DB" ]; then
    echo "ERROR: Source database not found at $SOURCE_DB"
    # Try to copy from backup/setup if available (handled by env setup usually)
    exit 1
fi

# 3. Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# 4. Focus DBeaver
focus_dbeaver || true

# 5. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Source: $SOURCE_DB"
echo "Target (to create): $TARGET_DB"