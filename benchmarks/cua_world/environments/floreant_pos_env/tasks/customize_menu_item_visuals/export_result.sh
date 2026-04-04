#!/bin/bash
echo "=== Exporting customize_menu_item_visuals results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if App is running
APP_RUNNING=$(pgrep -f "floreantpos.jar" > /dev/null && echo "true" || echo "false")

# 2. Query Database for the specific item
# We look for NAME, PRICE, BTN_COLOR, TEXT_COLOR
# Note: Column names in Floreant DB are typically BTN_COLOR and TEXT_COLOR for visuals
FLOREANT_LIB="/opt/floreantpos/lib"
CLASSPATH="$FLOREANT_LIB/derby.jar:$FLOREANT_LIB/derbytools.jar"
DB_URL="jdbc:derby:/opt/floreantpos/database/derby-server"

cat > /tmp/verify_item.sql << EOF
CONNECT '$DB_URL';
SELECT NAME, PRICE, BTN_COLOR, TEXT_COLOR, VISIBLE FROM MENU_ITEM WHERE NAME = 'Firecracker Shrimp';
EXIT;
EOF

echo "Querying database for 'Firecracker Shrimp'..."
# Run query and capture output
# We sleep briefly to ensure any background DB writes are flushed (Derby is embedded but usually writes on commit)
sleep 2
QUERY_OUTPUT=$(java -cp "$CLASSPATH" -Dderby.system.home=/opt/floreantpos org.apache.derby.tools.ij /tmp/verify_item.sql 2>&1)

# Save raw output for debugging
echo "$QUERY_OUTPUT" > /tmp/db_query_raw.txt

# 3. Get Final Item Count
cat > /tmp/count_items_final.sql << EOF
CONNECT '$DB_URL';
SELECT COUNT(*) FROM MENU_ITEM;
EXIT;
EOF
FINAL_COUNT_OUTPUT=$(java -cp "$CLASSPATH" -Dderby.system.home=/opt/floreantpos org.apache.derby.tools.ij /tmp/count_items_final.sql 2>/dev/null || echo "0")
FINAL_COUNT=$(echo "$FINAL_COUNT_OUTPUT" | grep -A 1 "1" | tail -1 | tr -d ' ' | grep -o "[0-9]*" || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_item_count.txt 2>/dev/null || echo "0")

# 4. Create JSON Result
# We will embed the raw query output string into the JSON.
# Python verifier will parse it. Escaping newlines is important for JSON.
ESCAPED_OUTPUT=$(echo "$QUERY_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "initial_item_count": $INITIAL_COUNT,
    "final_item_count": $FINAL_COUNT,
    "db_query_output": $ESCAPED_OUTPUT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="