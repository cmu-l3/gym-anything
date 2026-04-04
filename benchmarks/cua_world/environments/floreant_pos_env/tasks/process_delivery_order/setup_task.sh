#!/bin/bash
echo "=== Setting up Process Delivery Order task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Restore a clean database to avoid confusion with previous runs
kill_floreant
sleep 2

echo "Restoring clean database snapshot..."
# Try to find the backup created by setup_floreant.sh
DB_POSDB=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -n "$DB_POSDB" ] && [ -d /opt/floreantpos/posdb_backup ]; then
    rm -rf "$DB_POSDB"
    cp -r /opt/floreantpos/posdb_backup "$DB_POSDB"
    chown -R ga:ga "$DB_POSDB"
    echo "Database restored from backup."
elif [ -d /opt/floreantpos/derby_server_backup ]; then
    # Fallback for some structures
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup."
else
    echo "WARNING: No database backup found. Continuing with current state."
fi

# Start Floreant POS
# The app starts directly to the main terminal (DINE IN, TAKE OUT, HOME DELIVERY)
start_and_login

# Record initial ticket count to detect "Do Nothing"
# We'll use a simple count query via Derby
echo "Recording initial ticket count..."
DERBY_LIB="/opt/floreantpos/lib"
CLASSPATH="$DERBY_LIB/derby.jar:$DERBY_LIB/derbytools.jar:$DERBY_LIB/derbyclient.jar"
DB_URL="jdbc:derby:$DB_POSDB"

cat > /tmp/count_tickets.sql <<EOF
CONNECT '$DB_URL';
SELECT COUNT(*) FROM TICKET;
EXIT;
EOF

# Run query (if java/derby works)
if [ -n "$DB_POSDB" ]; then
    java -cp "$CLASSPATH" org.apache.derby.tools.ij /tmp/count_tickets.sql > /tmp/initial_ticket_count_raw.txt 2>&1 || echo "Query failed"
    # Parse the number (usually the line after the header)
    grep -A 1 "1" /tmp/initial_ticket_count_raw.txt | tail -n 1 | tr -d ' ' > /tmp/initial_count.txt
else
    echo "0" > /tmp/initial_count.txt
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="