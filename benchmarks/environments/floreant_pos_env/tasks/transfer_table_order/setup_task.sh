#!/bin/bash
echo "=== Setting up transfer_table_order task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance to release DB locks
kill_floreant

# 2. Restore clean database (CRITICAL: Ensures tables are empty at start)
echo "Restoring clean database snapshot..."
# Locate the DB directory
DB_DIR="/opt/floreantpos/database/derby-server"
BACKUP_DIR="/opt/floreantpos/derby_server_backup"

if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from backup."
else
    echo "WARNING: No database backup found. Using current state (may be dirty)."
fi

# 3. Start Floreant POS
# This function (from task_utils.sh) launches the app and waits for the window
start_and_login

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="