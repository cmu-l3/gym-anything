#!/bin/bash
set -e
echo "=== Setting up configure_shift task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Floreant instance to ensure clean DB access
kill_floreant
sleep 2

# Restore clean database to ensure a known starting state
echo "Restoring clean database..."
DB_LIVE_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -d "/opt/floreantpos/posdb_backup" ] && [ -n "$DB_LIVE_DIR" ]; then
    rm -rf "$DB_LIVE_DIR"
    cp -r /opt/floreantpos/posdb_backup "$DB_LIVE_DIR"
    chown -R ga:ga "$DB_LIVE_DIR"
    echo "Database restored from backup."
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
fi

# Explicitly remove the target shift if it exists (Anti-gaming)
echo "Ensuring 'Early Bird' shift does not exist..."
export CLASSPATH="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"
mkdir -p /tmp/derby_scripts
cat > /tmp/derby_scripts/clean_shift.sql <<EOF
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
DELETE FROM SHIFT WHERE NAME = 'Early Bird';
exit;
EOF

# Run the SQL cleanup
java -Dderby.system.home=/opt/floreantpos/database/derby-server org.apache.derby.tools.ij /tmp/derby_scripts/clean_shift.sql > /dev/null 2>&1 || true

# Start Floreant POS and get to the main screen
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="