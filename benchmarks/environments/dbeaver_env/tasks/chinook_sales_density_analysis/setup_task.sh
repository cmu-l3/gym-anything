#!/bin/bash
# Setup script for chinook_sales_density_analysis
# Ensures Chinook DB exists and cleans up any previous attempts

set -e
echo "=== Setting up Chinook Sales Density Analysis Task ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"

# Ensure export directory exists
mkdir -p "$EXPORT_DIR"
chown ga:ga "$EXPORT_DIR"

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# Clean up previous state (if retrying)
if [ -f "$DB_PATH" ]; then
    echo "Cleaning up previous artifacts in database..."
    sqlite3 "$DB_PATH" "DROP VIEW IF EXISTS v_monthly_density;" 2>/dev/null || true
    sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS dim_date;" 2>/dev/null || true
fi

# Remove previous export
rm -f "$EXPORT_DIR/sales_density.csv"

# Record initial state
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="