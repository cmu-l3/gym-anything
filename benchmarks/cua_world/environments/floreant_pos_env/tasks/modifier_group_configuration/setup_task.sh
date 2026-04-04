#!/bin/bash
# pre_task hook for modifier_group_configuration

echo "=== Setting up modifier_group_configuration task ==="

source /workspace/scripts/task_utils.sh

kill_floreant
sleep 1

echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup."
else
    echo "WARNING: No backup found."
fi

date +%s > /tmp/task_start_timestamp

start_and_login
sleep 3

take_screenshot /tmp/floreant_task_start.png

echo "=== modifier_group_configuration setup complete ==="
