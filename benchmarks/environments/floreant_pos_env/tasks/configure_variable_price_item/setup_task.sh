#!/bin/bash
echo "=== Setting up Configure Variable Price Item task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Restore a clean database to ensure "Fresh Catch" doesn't already exist
kill_floreant
sleep 1
echo "Restoring clean database snapshot..."

# Try to find the backup created by setup_floreant.sh
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
BACKUP_DIR="/opt/floreantpos/posdb_backup"

if [ -n "$DB_POSDB" ] && [ -d "$BACKUP_DIR" ]; then
    rm -rf "$DB_POSDB"
    cp -r "$BACKUP_DIR" "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
else
    echo "WARNING: Clean database backup not found, proceeding with current state."
fi

# Start Floreant POS and log in/show main screen
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="