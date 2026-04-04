#!/bin/bash
set -e
echo "=== Setting up add_employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# Restore clean database state
# -----------------------------------------------------------------------
echo "Restoring clean database state..."
kill_floreant
sleep 2

DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
BACKUP_DIR=""

if [ -d "/opt/floreantpos/posdb_backup" ]; then
    BACKUP_DIR="/opt/floreantpos/posdb_backup"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    BACKUP_DIR="/opt/floreantpos/derby_server_backup"
fi

if [ -n "$BACKUP_DIR" ] && [ -n "$DB_DIR" ]; then
    echo "Restoring DB from $BACKUP_DIR to $DB_DIR..."
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
fi

# -----------------------------------------------------------------------
# Record Initial DB State
# -----------------------------------------------------------------------
# Count initial users to detect changes later
echo "Querying initial user count..."
INITIAL_USER_COUNT=0

DERBY_JARS=""
for jar in /opt/floreantpos/lib/derby*.jar; do
    [ -f "$jar" ] && DERBY_JARS="${DERBY_JARS}:$jar"
done

# Remove leading colon
DERBY_JARS="${DERBY_JARS#:}"

if [ -n "$DERBY_JARS" ] && [ -n "$DB_DIR" ]; then
    # Create simple SQL script
    echo "connect 'jdbc:derby:$DB_DIR';" > /tmp/count_users.sql
    echo "SELECT COUNT(*) FROM USERS;" >> /tmp/count_users.sql
    echo "exit;" >> /tmp/count_users.sql
    
    # Run query
    INITIAL_USER_COUNT=$(java -cp "$DERBY_JARS" org.apache.derby.tools.ij /tmp/count_users.sql 2>/dev/null | grep -A 1 "COUNT" | tail -1 | tr -d ' ' || echo "0")
    echo "Initial user count: $INITIAL_USER_COUNT"
fi
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# -----------------------------------------------------------------------
# Start Application
# -----------------------------------------------------------------------
echo "Starting Floreant POS..."
start_and_login
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved"

# Verify Floreant is running
if pgrep -f "floreantpos.jar" > /dev/null 2>&1; then
    echo "Floreant POS is running"
else
    echo "WARNING: Floreant POS may not be running"
fi

echo "=== add_employee task setup complete ==="