#!/bin/bash
set -e
echo "=== Exporting create_discount_coupon results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# Step 1: Capture Final State & Cleanup
# -----------------------------------------------------------------------
# Take final screenshot BEFORE killing the app
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Stop Floreant POS to release Derby DB lock for querying
echo "Stopping Floreant POS for verification..."
pkill -f "floreantpos.jar" 2>/dev/null || true
sleep 3
pkill -9 -f "floreantpos.jar" 2>/dev/null || true
sleep 2

# -----------------------------------------------------------------------
# Step 2: Query Database
# -----------------------------------------------------------------------
DB_DIR=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

# Build classpath
DERBY_CP=""
for jar in /opt/floreantpos/lib/derby*.jar; do
    if [ -f "$jar" ]; then
        DERBY_CP="${DERBY_CP}:${jar}"
    fi
done
DERBY_CP="${DERBY_CP}:/opt/floreantpos/lib/*"
DERBY_CP="${DERBY_CP#:}"

# Find correct table name if needed
COUPON_TABLE="COUPON_AND_DISCOUNT"
cat > /tmp/check_table.sql << 'SQLEOF'
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT TABLENAME FROM SYS.SYSTABLES WHERE TABLETYPE='T' AND TABLENAME LIKE '%COUPON%';
DISCONNECT;
EXIT;
SQLEOF
TABLE_CHECK=$(cd /opt/floreantpos && java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/check_table.sql 2>/dev/null || echo "")
if echo "$TABLE_CHECK" | grep -q "COUPON_AND_DISCOUNT"; then
    COUPON_TABLE="COUPON_AND_DISCOUNT"
elif echo "$TABLE_CHECK" | grep -q "COUPONS"; then
    COUPON_TABLE="COUPONS"
fi

# Query all data from table
cat > /tmp/verify_coupons.sql << SQLEOF
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT * FROM $COUPON_TABLE;
DISCONNECT;
EXIT;
SQLEOF

QUERY_OUTPUT=$(cd /opt/floreantpos && java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/verify_coupons.sql 2>/dev/null || echo "QUERY_FAILED")

# Get current count
cat > /tmp/verify_count.sql << SQLEOF2
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT COUNT(*) AS CNT FROM $COUPON_TABLE;
DISCONNECT;
EXIT;
SQLEOF2

COUNT_RESULT=$(cd /opt/floreantpos && java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/verify_count.sql 2>/dev/null || echo "0")
CURRENT_COUNT=$(echo "$COUNT_RESULT" | grep -oE '^[0-9]+' | head -1)
CURRENT_COUNT=${CURRENT_COUNT:-0}
INITIAL_COUNT=$(cat /tmp/initial_coupon_count.txt 2>/dev/null || echo "0")

# Check for DB modifications (anti-gaming)
DB_MODIFIED="false"
if [ -n "$DB_DIR" ]; then
    CURRENT_HASH=$(find "$DB_DIR" -type f -exec md5sum {} + | sort | md5sum)
    INITIAL_HASH=$(cat /tmp/initial_db_hash.txt 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        DB_MODIFIED="true"
    fi
fi

# Parse specific coupon details (Weekend Special)
# We handle parsing in Python via the exported raw output, 
# but we can do a quick check here for the name
HAS_COUPON_NAME="false"
if echo "$QUERY_OUTPUT" | grep -iq "Weekend Special"; then
    HAS_COUPON_NAME="true"
fi

# -----------------------------------------------------------------------
# Step 3: Create Result JSON
# -----------------------------------------------------------------------
# Save raw query output to a file for Python to parse if needed, 
# but for simplicity we'll embed the relevant raw lines in JSON
# (We filter to avoid massive JSONs)
RAW_LINES=$(echo "$QUERY_OUTPUT" | grep -i "Weekend Special" | head -5)

# Escape quotes for JSON
ESCAPED_RAW=$(echo "$RAW_LINES" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
ESCAPED_FULL_OUTPUT=$(echo "$QUERY_OUTPUT" | head -n 100 | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "db_modified": $DB_MODIFIED,
    "has_coupon_name": $HAS_COUPON_NAME,
    "target_coupon_raw": "$ESCAPED_RAW",
    "full_query_output": "$ESCAPED_FULL_OUTPUT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="