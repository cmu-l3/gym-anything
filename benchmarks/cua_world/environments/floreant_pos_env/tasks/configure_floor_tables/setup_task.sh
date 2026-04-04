#!/bin/bash
set -e
echo "=== Setting up configure_floor_tables task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Floreant instance to ensure clean DB access
kill_floreant
sleep 2

# Restore clean database state from backup (critical for reproducible ID assignment)
echo "Restoring clean database..."
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
BACKUP_DIR="/opt/floreantpos/posdb_backup"

if [ -d "$BACKUP_DIR" ] && [ -n "$DB_DIR" ]; then
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from backup"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    # Fallback backup location
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup"
fi

# Start Floreant POS and wait for main terminal screen
start_and_login

# Take screenshot of initial state
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Floreant POS is running on the main terminal screen."
echo "Agent should: click BACK OFFICE → enter PIN 1111 → add Patio floor → add 4 tables"