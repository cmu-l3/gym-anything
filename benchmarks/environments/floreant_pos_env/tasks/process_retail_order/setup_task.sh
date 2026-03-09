#!/bin/bash
set -e
echo "=== Setting up Retail Order Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- DB STATE RECORDING ---
# We need to record the initial number of closed retail tickets to detect new ones later.
# First, ensure Floreant is closed so we can access the embedded Derby DB.
kill_floreant
sleep 2

# Locate database and Derby jars
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    DB_DIR="/opt/floreantpos/database/derby-server/POSDB"
fi
DERBY_LIB="/opt/floreantpos/lib"
DERBY_CLASSPATH="$DERBY_LIB/derby.jar:$DERBY_LIB/derbytools.jar"

echo "Recording initial DB state from $DB_DIR..."

# Query 1: Total closed tickets
# Query 2: Total closed RETAIL tickets
INITIAL_COUNTS=$(java -cp "$DERBY_CLASSPATH" org.apache.derby.tools.ij 2>/dev/null <<SQLEOF
connect 'jdbc:derby:$DB_DIR;create=false';
SELECT COUNT(*) FROM TICKET WHERE CLOSED = true;
SELECT COUNT(*) FROM TICKET WHERE TICKET_TYPE = 'RETAIL' AND CLOSED = true;
disconnect;
exit;
SQLEOF
)

# Parse output (ij output is verbose, we grab the numbers)
# Expected output format includes headers, so we grep for digits
INITIAL_TOTAL=$(echo "$INITIAL_COUNTS" | grep -A 1 "1" | grep -oE '[0-9]+' | head -1 || echo "0")
INITIAL_RETAIL=$(echo "$INITIAL_COUNTS" | grep -A 1 "1" | grep -oE '[0-9]+' | tail -1 || echo "0")

echo "$INITIAL_TOTAL" > /tmp/initial_total_tickets.txt
echo "$INITIAL_RETAIL" > /tmp/initial_retail_tickets.txt

echo "Initial Total Closed: $INITIAL_TOTAL"
echo "Initial Retail Closed: $INITIAL_RETAIL"

# --- APPLICATION LAUNCH ---
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="