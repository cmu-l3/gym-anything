#!/bin/bash
echo "=== Exporting Configure Dine-In Workflow Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of operational check)
take_screenshot /tmp/task_final.png

# 2. Kill Floreant POS to release the Derby database lock
# We need to query the embedded DB, which only allows one connection at a time
echo "Stopping Floreant POS to check database configuration..."
kill_floreant

# 3. Query the Derby Database
# We need to check the ORDER_TYPE table for NAME='DINE IN' and SHOW_GUEST_SELECTION status

# Locate database path
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    # Fallback search
    DB_PATH=$(find /opt/floreantpos/database -type d -name "posdb" 2>/dev/null | head -1)
fi

echo "Database path: $DB_PATH"

# Construct Classpath for Derby tools
# Floreant usually ships derby jars in /opt/floreantpos/lib/
CP=$(find /opt/floreantpos/lib -name "derby*.jar" | tr '\n' ':')
if [ -z "$CP" ]; then
    echo "ERROR: Could not find derby jars"
    CP="/opt/floreantpos/lib/*"
fi

# Create a SQL script
cat > /tmp/query_ordertype.sql << SQL_EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT NAME, SHOW_GUEST_SELECTION FROM ORDER_TYPE WHERE NAME = 'DINE IN';
DISCONNECT;
EXIT;
SQL_EOF

# Run ij tool
echo "Running Derby query..."
java -cp "$CP" org.apache.derby.tools.ij /tmp/query_ordertype.sql > /tmp/db_query_output.txt 2>&1

echo "--- Query Output ---"
cat /tmp/db_query_output.txt
echo "--------------------"

# Parse the output for the result
# Expected output format in ij:
# NAME                |SHOW_&
# ---------------------------
# DINE IN             |0     
# or
# DINE IN             |false 

# We look for "DINE IN" and the value associated with it
GUEST_SELECTION_VALUE="unknown"

if grep -q "DINE IN" /tmp/db_query_output.txt; then
    # Extract the line containing DINE IN
    LINE=$(grep "DINE IN" /tmp/db_query_output.txt)
    # Extract the last column (ignoring whitespace)
    # Values could be 0, 1, true, false
    if echo "$LINE" | grep -q "0\|false\|FALSE"; then
        GUEST_SELECTION_VALUE="false"
    elif echo "$LINE" | grep -q "1\|true\|TRUE"; then
        GUEST_SELECTION_VALUE="true"
    fi
fi

# 4. Prepare Result JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Save to temporary JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "guest_selection_value": "$GUEST_SELECTION_VALUE",
    "db_query_raw": "$(cat /tmp/db_query_output.txt | tr -d '\n' | sed 's/"/\\"/g')"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"