#!/bin/bash
set -e
echo "=== Setting up add_cooking_instruction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Floreant instance to unlock DB
kill_floreant
sleep 2

# -----------------------------------------------------------------------
# Restore clean database
# -----------------------------------------------------------------------
echo "Restoring clean database..."
DB_LIVE_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -d "/opt/floreantpos/posdb_backup" ] && [ -n "$DB_LIVE_DIR" ]; then
    rm -rf "$DB_LIVE_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_LIVE_DIR"
    chown -R ga:ga "$DB_LIVE_DIR"
    echo "Database restored from backup to $DB_LIVE_DIR"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    # Fallback location
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup"
fi

# -----------------------------------------------------------------------
# Record initial DB state (Anti-gaming)
# -----------------------------------------------------------------------
# Calculate MD5 of the main data segment to detect changes later
DB_SEG_DIR=$(find /opt/floreantpos/database -name "seg0" -type d 2>/dev/null | head -1)
if [ -n "$DB_SEG_DIR" ]; then
    find "$DB_SEG_DIR" -type f -exec md5sum {} \; | sort > /tmp/initial_db_checksums.txt
    echo "Initial DB checksums recorded."
else
    echo "WARNING: Could not find DB segment directory for checksums."
    touch /tmp/initial_db_checksums.txt
fi

# -----------------------------------------------------------------------
# Launch Application
# -----------------------------------------------------------------------
# start_and_login launches app, waits for window, maximizes, and focuses
start_and_login

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="