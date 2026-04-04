#!/bin/bash
echo "=== Exporting add_employee task result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# 1. Capture Final State Visuals
# -----------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# 2. Database Verification
# -----------------------------------------------------------------------
# We MUST kill the app to release the Derby DB lock before querying
echo "Stopping Floreant POS for database verification..."
kill_floreant
sleep 3

# Find Derby resources
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
DERBY_JARS=""
for jar in /opt/floreantpos/lib/derby*.jar; do
    [ -f "$jar" ] && DERBY_JARS="${DERBY_JARS}:$jar"
done
DERBY_JARS="${DERBY_JARS#:}"

# Initialize result variables
USER_FOUND="false"
USER_DETAILS="{}"
DB_MODIFIED="false"

# Check file modification timestamps
if [ -n "$DB_PATH" ]; then
    # Check if any file in DB dir is newer than start time
    NEWEST_FILE=$(find "$DB_PATH" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEWEST_FILE" ]; then
        DB_MODIFIED="true"
    fi
fi

# Query Database
if [ -n "$DERBY_JARS" ] && [ -n "$DB_PATH" ]; then
    echo "Querying database for 'Maria Santos'..."
    
    # Create query script
    # Note: Column names based on standard Floreant schema (USERS table)
    cat > /tmp/check_user.sql << EOF
connect 'jdbc:derby:$DB_PATH';
SELECT FIRST_NAME, LAST_NAME, USER_TYPE, PASSWORD, COST_PER_HOUR FROM USERS WHERE UPPER(FIRST_NAME) LIKE '%MARIA%';
exit;
EOF

    # Run query and capture output
    QUERY_OUTPUT=$(java -cp "$DERBY_JARS" org.apache.derby.tools.ij /tmp/check_user.sql 2>/dev/null)
    echo "Query Output:"
    echo "$QUERY_OUTPUT"
    
    # Simple grep parsing to avoid complex logic in bash
    # We will verify details in Python, here we just extract raw rows
    if echo "$QUERY_OUTPUT" | grep -iq "MARIA"; then
        USER_FOUND="true"
        
        # Extract the row containing Maria
        ROW=$(echo "$QUERY_OUTPUT" | grep -i "MARIA" | head -1)
        
        # Clean up row for JSON (remove extra spaces)
        CLEAN_ROW=$(echo "$ROW" | sed 's/[[:space:]]\+/ /g')
        
        # Construct JSON object manually
        USER_DETAILS="{\"raw_row\": \"$CLEAN_ROW\"}"
    fi
fi

# -----------------------------------------------------------------------
# 3. Create Result JSON
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_modified": $DB_MODIFIED,
    "user_found": $USER_FOUND,
    "user_details": $USER_DETAILS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="