#!/bin/bash
echo "=== Setting up update_receipt_footer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean state by restoring DB backup
# This ensures the footer isn't already set to the target value
kill_floreant
sleep 2

echo "Restoring clean database snapshot..."
# Use the backup created in setup_floreant.sh
if [ -d /opt/floreantpos/posdb_backup ]; then
    DB_PARENT=$(dirname "$(find /opt/floreantpos/database -name "service.properties" | head -1)")
    if [ -n "$DB_PARENT" ]; then
        rm -rf "$DB_PARENT"
        cp -r /opt/floreantpos/posdb_backup "$DB_PARENT"
        chown -R ga:ga "$DB_PARENT"
    fi
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback structure
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
fi

# 2. Launch Application
start_and_login

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="