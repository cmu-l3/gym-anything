#!/bin/bash
set -e
echo "=== Setting up Configure Printer Routing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Database to clean state
# This ensures "Bar Printer" does not exist and "Beverages" has default routing
kill_floreant
sleep 2

echo "Restoring clean database snapshot..."
# Prefer the backup created by install/setup scripts
if [ -d /opt/floreantpos/posdb_backup ]; then
    DB_DIR=$(find /opt/floreantpos/database -name "service.properties" | head -1 | xargs dirname)
    if [ -n "$DB_DIR" ]; then
        rm -rf "$DB_DIR"
        cp -r /opt/floreantpos/posdb_backup "$DB_DIR"
        chown -R ga:ga "$DB_DIR"
        echo "Database restored from posdb_backup."
    fi
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback structure
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup."
fi

# 2. Start Floreant POS
start_and_login

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="