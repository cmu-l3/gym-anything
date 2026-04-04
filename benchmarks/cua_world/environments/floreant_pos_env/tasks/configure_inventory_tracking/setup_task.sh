#!/bin/bash
echo "=== Setting up Configure Inventory Tracking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous run's data (Reset DB)
# We need to ensure 'Surf and Turf' doesn't exist yet.
kill_floreant
sleep 2

echo "Restoring clean database to ensure pristine state..."
# Identify where the DB lives
DB_DIR="/opt/floreantpos/database/derby-server/posdb"
BACKUP_DIR="/opt/floreantpos/posdb_backup"

if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored."
else
    echo "WARNING: No backup found at $BACKUP_DIR. Proceeding with current DB."
fi

# 2. Start Floreant POS
start_and_login

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="