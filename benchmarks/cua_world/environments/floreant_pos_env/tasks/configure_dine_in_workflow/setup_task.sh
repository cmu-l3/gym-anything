#!/bin/bash
echo "=== Setting up Configure Dine-In Workflow Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance to ensure we can manipulate DB if needed
kill_floreant
sleep 2

# 2. Restore clean database to ensure default state (Show Guest Selection = TRUE)
echo "Restoring clean database snapshot..."
# Locate the database directory
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
    echo "WARNING: No database backup found. Task may start in modified state."
fi

# 3. Start Floreant POS
# This function handles the launch, wait, maximize, and focus
start_and_login

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Disable 'Show Guest Selection' for DINE IN order type."