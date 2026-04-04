#!/bin/bash
echo "=== Setting up Void Settled Transaction task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Database Setup & Initial State Recording
# ==============================================================================

# Ensure we have a clean state or at least know the current max ticket ID
# to distinguish new agent actions from old history.

# We need to query the Derby DB.
# First, ensure app is stopped to release DB lock.
kill_floreant

# Define classpath for Derby tools
DERBY_LIB_DIR="/opt/floreantpos/lib"
CLASSPATH="$DERBY_LIB_DIR/derby.jar:$DERBY_LIB_DIR/derbytools.jar:$DERBY_LIB_DIR/derbyclient.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server/posdb"

# Query MAX(ID) from TICKET table
echo "Getting initial Ticket ID..."
MAX_ID_QUERY="SELECT MAX(ID) FROM TICKET;"
echo "$MAX_ID_QUERY" > /tmp/query_max_id.sql

# Run query using java/ij
# We use 'connect' inside the script passed to ij
cat > /tmp/run_query.sql << SQL_EOF
CONNECT '$DB_URL';
SELECT MAX(ID) FROM TICKET;
EXIT;
SQL_EOF

INITIAL_MAX_ID="0"
if [ -f "$DERBY_LIB_DIR/derbytools.jar" ]; then
    QUERY_RESULT=$(java -cp "$CLASSPATH" org.apache.derby.tools.ij /tmp/run_query.sql 2>/dev/null | grep -o "[0-9]*" | tail -1)
    if [ -n "$QUERY_RESULT" ]; then
        INITIAL_MAX_ID="$QUERY_RESULT"
    fi
else
    echo "WARNING: Derby jars not found, assuming ID start 0"
fi

echo "$INITIAL_MAX_ID" > /tmp/initial_max_ticket_id.txt
echo "Initial Max Ticket ID: $INITIAL_MAX_ID"

# ==============================================================================
# 2. Launch Application
# ==============================================================================

# Start Floreant POS
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="