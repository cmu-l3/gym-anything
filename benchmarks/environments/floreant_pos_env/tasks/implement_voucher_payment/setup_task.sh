#!/bin/bash
echo "=== Setting up implement_voucher_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore a clean database to ensure 'Marketing Voucher' does not exist yet
kill_floreant
sleep 1

echo "Restoring clean database snapshot..."
# Locate database directory
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback structure
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
else
    echo "WARNING: No database backup found; proceeding with current state."
fi

# 2. Start Floreant POS
start_and_login

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="