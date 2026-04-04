#!/bin/bash
# pre_task hook for multi_rate_tax_compliance
# Restores clean database, then launches Floreant POS

echo "=== Setting up multi_rate_tax_compliance task ==="

source /workspace/scripts/task_utils.sh

# Kill any running Floreant instance
kill_floreant
sleep 1

# Restore clean database backup
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from posdb_backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup."
else
    echo "WARNING: No database backup found; proceeding without restore."
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch Floreant POS
start_and_login
sleep 3

# Take initial screenshot
take_screenshot /tmp/floreant_task_start.png
echo "Initial screenshot saved."

echo "=== multi_rate_tax_compliance setup complete ==="
