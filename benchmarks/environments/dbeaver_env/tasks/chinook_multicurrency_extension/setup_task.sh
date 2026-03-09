#!/bin/bash
# Setup script for chinook_multicurrency_extension task

set -e
echo "=== Setting up Chinook Multi-Currency Extension Task ==="

source /workspace/scripts/task_utils.sh

# Paths
ORIGINAL_DB="/home/ga/Documents/databases/chinook.db"
EXTENDED_DB="/home/ga/Documents/databases/chinook_extended.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

# Ensure directories exist
mkdir -p "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous artifacts
rm -f "$EXPORT_DIR/currency_revenue.csv"
rm -f "$SCRIPTS_DIR/multicurrency_migration.sql"
rm -f "$EXTENDED_DB"

# Ensure source database exists
if [ ! -f "$ORIGINAL_DB" ]; then
    echo "ERROR: Original Chinook database not found at $ORIGINAL_DB"
    # Attempt to restore from backup or standard location if possible
    if [ -f "/workspace/data/chinook.db" ]; then
        cp "/workspace/data/chinook.db" "$ORIGINAL_DB"
    else
        echo "FATAL: Could not locate chinook.db"
        exit 1
    fi
fi

# Create the working copy database
echo "Creating working copy: $EXTENDED_DB"
cp "$ORIGINAL_DB" "$EXTENDED_DB"
chown ga:ga "$EXTENDED_DB"
chmod 644 "$EXTENDED_DB"

# Calculate checksum of original DB to ensure it's not modified during task
md5sum "$ORIGINAL_DB" | awk '{print $1}' > /tmp/original_db_checksum

# Record initial file counts
echo "Recording initial state..."
date +%s > /tmp/task_start_time

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver and maximize
focus_dbeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Working Database: $EXTENDED_DB"