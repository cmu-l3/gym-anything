#!/bin/bash
set -e
echo "=== Setting up create_service_charge task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Database (Clean State)
# Kill any running instance to release DB lock
kill_floreant
sleep 1

# Restore backup to ensure "Large Party" doesn't already exist
echo "Restoring clean database..."
if [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server/posdb
    cp -r /opt/floreantpos/posdb_backup /opt/floreantpos/database/derby-server/posdb
    chown -R ga:ga /opt/floreantpos/database/derby-server/posdb
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
fi

# 2. Record Initial State (Check if 'Large Party' exists - shouldn't, but good to verify)
# We use ij to query Derby
echo "Checking initial database state..."
mkdir -p /tmp/db_check
cat > /tmp/db_check/check_initial.sql << EOF
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT COUNT(*) FROM GRATUITY;
SELECT NAME FROM GRATUITY WHERE UPPER(NAME) LIKE '%LARGE PARTY%';
exit;
EOF

# Execute query (ignore errors if table doesn't exist yet in this version)
export CLASSPATH="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"
java org.apache.derby.tools.ij /tmp/db_check/check_initial.sql > /tmp/initial_db_state.txt 2>&1 || true

# Extract count
INITIAL_COUNT=$(grep -A 1 "COUNT" /tmp/initial_db_state.txt | tail -n 1 | tr -d ' ' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_gratuity_count.txt
echo "Initial gratuity count: $INITIAL_COUNT"

# 3. Launch Application
start_and_login

# 4. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="