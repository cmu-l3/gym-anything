#!/bin/bash
echo "=== Exporting add_kitchen_printer result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot before killing the app
take_screenshot /tmp/task_final_state.png

# 2. Check if application was running
APP_WAS_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# 3. Kill Floreant to release Derby database lock
echo "Stopping Floreant POS to verify database..."
kill_floreant
sleep 3

# 4. Verify Database State
# We look for the specific printer name "Kitchen-Expo-1"
TARGET_NAME="Kitchen-Expo-1"

echo "Querying database for printer '$TARGET_NAME'..."
DB_RESULT=$(java -Dderby.system.home=/opt/floreantpos/database/derby-server \
    -cp "/opt/floreantpos/lib/*" org.apache.derby.tools.ij 2>/dev/null <<EOF
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT NAME FROM VIRTUAL_PRINTER WHERE UPPER(NAME) = UPPER('$TARGET_NAME');
EOF
)

# Check if we found the name in the output
PRINTER_FOUND="false"
if echo "$DB_RESULT" | grep -qi "$TARGET_NAME"; then
    PRINTER_FOUND="true"
    echo "Printer found in database."
else
    echo "Printer NOT found in database."
    echo "DEBUG DB OUTPUT: $DB_RESULT"
fi

# 5. Check row count change
INITIAL_COUNT=$(cat /tmp/initial_printer_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(java -Dderby.system.home=/opt/floreantpos/database/derby-server \
    -cp "/opt/floreantpos/lib/*" org.apache.derby.tools.ij 2>/dev/null <<EOF | grep -o "[0-9]*" | tail -1 || echo "0"
connect 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT COUNT(*) FROM VIRTUAL_PRINTER;
EOF
)
FINAL_COUNT=$(echo "$FINAL_COUNT" | tr -d '[:space:]')
if [ -z "$FINAL_COUNT" ]; then FINAL_COUNT="0"; fi

COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))
echo "Printer count change: $INITIAL_COUNT -> $FINAL_COUNT (Diff: $COUNT_DIFF)"

# 6. Create result JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "printer_found": $PRINTER_FOUND,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "count_diff": $COUNT_DIFF,
    "app_was_running": $APP_WAS_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="