#!/bin/bash
echo "=== Setting up configure_modifier_limits task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Restore a clean database state to ensure consistency
# This prevents previous failed runs from leaving the DB in a solved state
echo "Restoring clean database snapshot..."
kill_floreant
sleep 2

DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
else
    echo "WARNING: No database backup found; proceeding with current state."
fi

# Start Floreant POS and show the main screen
# The agent will handle the login (PIN 1111) as part of the task
start_and_login

# Take initial screenshot of the starting state
take_screenshot /tmp/floreant_initial.png

echo "=== Task setup complete ==="