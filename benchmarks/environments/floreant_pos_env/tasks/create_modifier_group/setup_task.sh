#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_modifier_group task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running instance to ensure we can restore DB
kill_floreant
sleep 2

# Restore clean database from backup (ensures reproducible starting state)
# We need to ensure 'Cooking Temperature' group doesn't already exist
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -d "/opt/floreantpos/posdb_backup" ] && [ -n "$DB_DIR" ]; then
    echo "Restoring clean database from posdb_backup..."
    rm -rf "$DB_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    echo "Restoring clean Derby server from backup..."
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
fi

# Start Floreant POS
# This function handles display setup, maximizing, and focusing
start_and_login

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="