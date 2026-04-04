#!/bin/bash
echo "=== Exporting disable_home_delivery results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state (App should still be running showing main screen without the button)
take_screenshot /tmp/task_final.png

# 2. Check if App is running
APP_RUNNING="false"
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Stop App to release Database Lock (Critical for Derby embedded)
kill_floreant

# 4. Query Database for Order Type visibility
echo "Querying database..."
export CLASSPATH=$CLASSPATH:/opt/floreantpos/lib/derby.jar:/opt/floreantpos/lib/derbytools.jar
DB_PROP=$(find /opt/floreantpos/database -name "service.properties" | head -1)
DB_PATH=$(dirname "$DB_PROP")

cat > /tmp/check_db.sql << EOF
CONNECT 'jdbc:derby:$DB_PATH';
SELECT NAME, VISIBLE FROM ORDER_TYPE;
EXIT;
EOF

# Run query and save raw output
java org.apache.derby.tools.ij /tmp/check_db.sql > /tmp/db_query_output.txt 2>&1

# 5. Parse DB output into JSON
# Output format is typically:
# NAME                |VISIBLE&
# -----------------------------
# DINE IN             |true    
# HOME DELIVERY       |false   

# Extract values using grep/awk
HOME_DELIVERY_VISIBLE=$(grep "HOME DELIVERY" /tmp/db_query_output.txt | grep -o "true\|false" || echo "unknown")
DINE_IN_VISIBLE=$(grep "DINE IN" /tmp/db_query_output.txt | grep -o "true\|false" || echo "unknown")
TAKE_OUT_VISIBLE=$(grep "TAKE OUT" /tmp/db_query_output.txt | grep -o "true\|false" || echo "unknown")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "home_delivery_visible": "$HOME_DELIVERY_VISIBLE",
    "dine_in_visible": "$DINE_IN_VISIBLE",
    "take_out_visible": "$TAKE_OUT_VISIBLE",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to final location
sudo mv "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="