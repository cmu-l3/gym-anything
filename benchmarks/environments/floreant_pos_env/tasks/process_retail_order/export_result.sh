#!/bin/bash
set -e
echo "=== Exporting Retail Order Task Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE killing app
take_screenshot /tmp/task_final.png

# Check if app was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# Stop Floreant to release DB lock for verification queries
kill_floreant
sleep 3

# --- DB VERIFICATION ---
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    DB_DIR="/opt/floreantpos/database/derby-server/POSDB"
fi
DERBY_LIB="/opt/floreantpos/lib"
DERBY_CLASSPATH="$DERBY_LIB/derby.jar:$DERBY_LIB/derbytools.jar"

# Load initial counts
INITIAL_TOTAL=$(cat /tmp/initial_total_tickets.txt 2>/dev/null || echo "0")
INITIAL_RETAIL=$(cat /tmp/initial_retail_tickets.txt 2>/dev/null || echo "0")

echo "Querying final DB state..."

# We need to find the ID of the MOST RECENT closed ticket to verify its properties
# We also count totals again to see if they increased
DB_OUTPUT=$(java -cp "$DERBY_CLASSPATH" org.apache.derby.tools.ij 2>/dev/null <<SQLEOF
connect 'jdbc:derby:$DB_DIR;create=false';

-- Get final counts
SELECT COUNT(*) FROM TICKET WHERE CLOSED = true;
SELECT COUNT(*) FROM TICKET WHERE TICKET_TYPE = 'RETAIL' AND CLOSED = true;

-- Get details of the last closed ticket
SELECT ID, TICKET_TYPE, TOTAL_AMOUNT FROM TICKET WHERE ID = (SELECT MAX(ID) FROM TICKET WHERE CLOSED = true);

-- Count items in that last ticket
SELECT COUNT(*) FROM TICKET_ITEM WHERE TICKET_ID = (SELECT MAX(ID) FROM TICKET WHERE CLOSED = true);

-- Check payment type for that last ticket (simplified check for CASH existence)
SELECT COUNT(*) FROM POS_TRANSACTION WHERE TICKET_ID = (SELECT MAX(ID) FROM TICKET WHERE CLOSED = true) AND PAYMENT_TYPE = 'CASH';

disconnect;
exit;
SQLEOF
)

# Parse Results using robust grep/awk
# Note: ij output is messy. We assume the order of SELECTs above.
# 1. Final Total Closed
FINAL_TOTAL=$(echo "$DB_OUTPUT" | grep -A 2 "SELECT COUNT(\*) FROM TICKET WHERE CLOSED = true" | grep -oE '[0-9]+' | tail -1 || echo "0")

# 2. Final Retail Closed
FINAL_RETAIL=$(echo "$DB_OUTPUT" | grep -A 2 "SELECT COUNT(\*) FROM TICKET WHERE TICKET_TYPE = 'RETAIL'" | grep -oE '[0-9]+' | tail -1 || echo "0")

# 3. Last Ticket Details (ID, TYPE)
# Use sed to extract the row after the header line
LAST_TICKET_ID=$(echo "$DB_OUTPUT" | grep -A 2 "ID " | tail -1 | awk '{print $1}' || echo "0")
LAST_TICKET_TYPE=$(echo "$DB_OUTPUT" | grep -A 2 "ID " | tail -1 | awk '{print $2}' || echo "UNKNOWN")

# 4. Item Count
ITEM_COUNT=$(echo "$DB_OUTPUT" | grep -A 2 "SELECT COUNT(\*) FROM TICKET_ITEM" | grep -oE '[0-9]+' | tail -1 || echo "0")

# 5. Cash Payment Count
CASH_PAYMENT_COUNT=$(echo "$DB_OUTPUT" | grep -A 2 "AND PAYMENT_TYPE = 'CASH'" | grep -oE '[0-9]+' | tail -1 || echo "0")

# Calculate differences
NEW_TOTAL_TICKETS=$((FINAL_TOTAL - INITIAL_TOTAL))
NEW_RETAIL_TICKETS=$((FINAL_RETAIL - INITIAL_RETAIL))

# Determine booleans
HAS_NEW_TICKET="false"
if [ "$NEW_TOTAL_TICKETS" -gt 0 ]; then HAS_NEW_TICKET="true"; fi

IS_RETAIL="false"
if [ "$LAST_TICKET_TYPE" == "RETAIL" ] && [ "$HAS_NEW_TICKET" == "true" ]; then IS_RETAIL="true"; fi

HAS_ITEMS="false"
if [ "$ITEM_COUNT" -ge 4 ]; then HAS_ITEMS="true"; fi # Task requires at least 4 items (3 distinct, one with qty 2)

PAID_CASH="false"
if [ "$CASH_PAYMENT_COUNT" -gt 0 ]; then PAID_CASH="true"; fi

# Construct JSON
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "initial_total": $INITIAL_TOTAL,
  "final_total": $FINAL_TOTAL,
  "new_tickets_created": $NEW_TOTAL_TICKETS,
  "last_ticket_id": "$LAST_TICKET_ID",
  "last_ticket_type": "$LAST_TICKET_TYPE",
  "is_retail_type": $IS_RETAIL,
  "item_count": $ITEM_COUNT,
  "paid_cash": $PAID_CASH,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="