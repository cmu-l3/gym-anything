#!/bin/bash
echo "=== Setting up create_menu_group task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running instance
kill_floreant

# 2. Restore clean DB to ensure 'Breakfast Specials' does not exist
echo "Restoring clean database snapshot..."
# Try to find the backup created by setup_floreant.sh
if [ -d /opt/floreantpos/posdb_backup ]; then
    # The DB is usually at /opt/floreantpos/database/derby-server/posdb
    # or defined in /opt/floreantpos/config/floreantpos.properties
    
    # We'll assume the standard location based on the install script
    DB_TARGET_DIR="/opt/floreantpos/database/derby-server/posdb"
    if [ -d "$DB_TARGET_DIR" ]; then
        rm -rf "$DB_TARGET_DIR"
        cp -r /opt/floreantpos/posdb_backup "$DB_TARGET_DIR"
        chown -R ga:ga "$DB_TARGET_DIR"
        echo "Database restored from posdb_backup."
    fi
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback to full derby server backup
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup."
else
    echo "WARNING: No database backup found. Proceeding with current state."
fi

# 3. Start Floreant POS
start_and_login

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="