#!/bin/bash
echo "=== Setting up verify_menu_order_workflow task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running instance to ensure clean DB restore
kill_floreant
sleep 2

# 2. Restore clean database to known state
# This ensures we don't detect items/orders from previous runs
echo "Restoring clean database snapshot..."
DB_DIR="/opt/floreantpos/database/derby-server"
BACKUP_DIR="/opt/floreantpos/derby_server_backup"

# Fallback to finding where the DB actually is if paths differ
if [ ! -d "$BACKUP_DIR" ]; then
    # Try finding the backup made by setup_floreant.sh
    BACKUP_DIR=$(find /opt/floreantpos -maxdepth 2 -name "*backup*" -type d | head -1)
fi

if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$DB_DIR"
    mkdir -p "$(dirname "$DB_DIR")"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    chmod -R 755 "$DB_DIR"
    echo "Database restored from $BACKUP_DIR"
else
    echo "WARNING: No database backup found. Starting with current state."
fi

# 3. Record Task Start Time
# Used to verify the ticket was created *during* this session
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Start Floreant POS
start_and_login

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="