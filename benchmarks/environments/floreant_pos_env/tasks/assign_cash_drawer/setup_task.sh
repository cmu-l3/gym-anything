#!/bin/bash
echo "=== Setting up assign_cash_drawer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "$(date -Iseconds)" > /tmp/task_start_iso.txt

# 1. Kill any running instances to ensure we can restore DB
kill_floreant
sleep 1

# 2. Restore clean database (CRITICAL: ensures no drawer is currently assigned)
# We need a state where the terminal is "closed" so "Assign Drawer" is available.
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback structure
    SERVER_DIR=$(dirname "$DB_POSDB")
    rm -rf "$SERVER_DIR"
    cp -r /opt/floreantpos/derby_server_backup "$SERVER_DIR"
    chown -R ga:ga "$SERVER_DIR"
    echo "Derby server restored from backup."
else
    echo "WARNING: No database backup found. Task may fail if drawer is already assigned."
fi

# 3. Start Floreant POS
start_and_login

# 4. Wait a bit for UI to settle
sleep 3

# 5. Capture initial state
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="
echo "Task: Assign Cash Drawer"
echo "Target: User 'Administrator', Amount '\$200.00'"