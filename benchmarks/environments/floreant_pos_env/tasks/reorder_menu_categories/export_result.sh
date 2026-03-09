#!/bin/bash
echo "=== Exporting Reorder Menu Categories results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final visual state before killing app
take_screenshot /tmp/task_final.png

# 2. Check if App was running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Kill App to release DB lock
kill_floreant

# 4. Query Database for Final State
DB_PATH=$(find /opt/floreantpos/database -type d -name "posdb" | head -1)
CP="/opt/floreantpos/lib/*:/opt/floreantpos/floreantpos.jar"

cat > /tmp/verify_db.sql <<EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT NAME, SORT_ORDER FROM MENU_CATEGORY WHERE UPPER(NAME) LIKE '%BEVERAGE%';
DISCONNECT;
EXIT;
EOF

chown ga:ga /tmp/verify_db.sql
# Run query and capture output
DB_OUTPUT=$(su - ga -c "java -cp '$CP' org.apache.derby.tools.ij /tmp/verify_db.sql" 2>&1)

# Extract Sort Order from output
# Output format is typically:
# NAME | SORT_ORDER
# -----------------
# BEVERAGES | 0
FINAL_SORT_ORDER=$(echo "$DB_OUTPUT" | grep -i "BEVERAGE" | awk -F '|' '{print $2}' | tr -d '[:space:]')
CATEGORY_NAME=$(echo "$DB_OUTPUT" | grep -i "BEVERAGE" | awk -F '|' '{print $1}' | tr -d '[:space:]')

if [ -z "$FINAL_SORT_ORDER" ]; then
    FINAL_SORT_ORDER="-1" # Category not found
fi

echo "Final DB State - Name: $CATEGORY_NAME, Sort Order: $FINAL_SORT_ORDER"

# 5. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "final_sort_order": "$FINAL_SORT_ORDER",
    "category_name": "$CATEGORY_NAME",
    "initial_sort_order": 99,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="