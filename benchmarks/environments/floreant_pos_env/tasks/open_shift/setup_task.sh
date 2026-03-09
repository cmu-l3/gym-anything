#!/bin/bash
# pre_task hook for open_shift task
# Sets up Floreant POS in a clean state (no open shifts)

echo "=== Setting up open_shift task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running instances
kill_floreant

# 2. Restore clean DB to ensure no stale shifts are open
# We rely on the backup created in setup_floreant.sh
echo "Restoring database to clean state..."
DB_DIR="/opt/floreantpos/database/derby-server"
BACKUP_DIR="/opt/floreantpos/derby_server_backup"

if [ -d "$BACKUP_DIR" ]; then
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    chmod -R 755 "$DB_DIR"
    echo "Database restored."
else
    echo "WARNING: Clean database backup not found. Proceeding with current DB."
fi

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Start Floreant POS
start_and_login

# 5. Capture Initial State Screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== open_shift setup complete ==="