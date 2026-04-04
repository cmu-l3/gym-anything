#!/bin/bash
echo "=== Exporting Configure Inventory Tracking Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Stop Floreant POS to release the Derby database lock
# (Embedded Derby locks the DB files while the app is running)
kill_floreant
sleep 3

# 3. Query the Derby Database to verify the item and stock
# We use the 'ij' tool included in Derby/JDK or Floreant libs
echo "Querying database..."

DB_PATH="/opt/floreantpos/database/derby-server/posdb"
EXPORT_FILE="/tmp/db_export.txt"

# Create a SQL script
cat > /tmp/query.sql << EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT NAME, PRICE, STOCK_AMOUNT, VISIBLE FROM MENU_ITEM WHERE LOWER(NAME) LIKE '%surf%';
EXIT;
EOF

# Find java and classpath
# Floreant usually ships jars in /opt/floreantpos/lib
CP="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"

# Run ij
java -cp "$CP" org.apache.derby.tools.ij /tmp/query.sql > "$EXPORT_FILE" 2>&1

echo "Database query result:"
cat "$EXPORT_FILE"

# 4. Prepare JSON result
# We'll parse the text file in Python verifier, but let's gather metadata here
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_WAS_RUNNING="true" # We killed it, so it was running

# Check if we got any rows
DB_HAS_DATA="false"
if grep -qi "Surf" "$EXPORT_FILE"; then
    DB_HAS_DATA="true"
fi

# Save raw output to a file that won't be overwritten
cp "$EXPORT_FILE" /tmp/menu_item_query_result.txt
chmod 666 /tmp/menu_item_query_result.txt

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_WAS_RUNNING,
    "db_query_run": true,
    "db_has_data": $DB_HAS_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="