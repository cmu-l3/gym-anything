#!/bin/bash
echo "=== Setting up create_floor_section task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean database to ensure "Patio" doesn't exist
kill_floreant
sleep 2

echo "Restoring clean database snapshot..."
# Try to find the backup created by setup_floreant.sh
if [ -d /opt/floreantpos/posdb_backup ]; then
    # Location 1: service.properties parent dir
    DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    if [ -n "$DB_POSDB" ]; then
        rm -rf "$DB_POSDB"
        cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
        chown -R ga:ga "$DB_POSDB"
        echo "Database restored from posdb_backup."
    fi
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Location 2: derby-server dir
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Database restored from derby_server_backup."
else
    echo "WARNING: No database backup found. Task might fail if 'Patio' already exists."
fi

# 2. Record initial floor count from DB
echo "Recording initial database state..."
# Construct classpath for Derby tools
DERBY_LIB="/opt/floreantpos/lib"
CP="$DERBY_LIB/derby.jar:$DERBY_LIB/derbytools.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server/posdb"

# Create SQL script to count floors
cat > /tmp/count_floors.sql << SQLEOF
CONNECT '$DB_URL';
SELECT COUNT(*) FROM SHOP_FLOOR;
EXIT;
SQLEOF

# Run query (as ga user to match db permissions)
INITIAL_FLOOR_COUNT=$(su - ga -c "java -cp $CP org.apache.derby.tools.ij /tmp/count_floors.sql" | grep -A 1 "1" | tail -n 1 | tr -d ' ' || echo "0")
echo "$INITIAL_FLOOR_COUNT" > /tmp/initial_floor_count.txt
echo "Initial floor count: $INITIAL_FLOOR_COUNT"

# 3. Start Floreant POS
start_and_login

# 4. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="