#!/bin/bash
# pre_task hook for configure_default_gratuity task
# Restores clean DB and starts Floreant POS

echo "=== Setting up configure_default_gratuity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance to release DB lock
kill_floreant
sleep 2

# 2. Restore clean database to ensure known starting state (Default Gratuity usually 0)
echo "Restoring clean database snapshot..."
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
else
    echo "WARNING: No database backup found; proceeding with current state."
fi

# 3. Start Floreant POS
start_and_login

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="