#!/bin/bash
echo "=== Setting up chefs_table_experience_launch task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running instance to ensure clean DB operations
kill_floreant
sleep 2

# 2. Restore clean database to prevent name collisions
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
fi

# 3. Delete stale outputs BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/db_query_output.txt 2>/dev/null || true

# 4. Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Floreant POS
start_and_login

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
