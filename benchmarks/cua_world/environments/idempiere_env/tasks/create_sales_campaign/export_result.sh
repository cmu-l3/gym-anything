#!/bin/bash
set -e
echo "=== Exporting create_sales_campaign results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get Client ID
CLIENT_ID=$(get_gardenworld_client_id)

# ------------------------------------------------------------------
# Query the Database for the specific record
# ------------------------------------------------------------------
TARGET_KEY="SPRING-GARDEN-2025"

# We fetch fields individually to handle potential nulls or formatting safely in bash
RECORD_EXISTS=$(idempiere_query "SELECT COUNT(*) FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

NAME=""
DESC=""
START_DATE=""
END_DATE=""
COSTS="0"
CREATED_EPOCH="0"
CREATED_BY=""

if [ "$RECORD_EXISTS" -gt 0 ]; then
    echo "Found campaign record."
    NAME=$(idempiere_query "SELECT name FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")
    DESC=$(idempiere_query "SELECT description FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")
    START_DATE=$(idempiere_query "SELECT TO_CHAR(startdate, 'YYYY-MM-DD') FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")
    END_DATE=$(idempiere_query "SELECT TO_CHAR(enddate, 'YYYY-MM-DD') FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")
    COSTS=$(idempiere_query "SELECT costs FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
    CREATED_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::bigint FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
    CREATED_BY=$(idempiere_query "SELECT createdby FROM c_campaign WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
else
    echo "Campaign record not found."
fi

# Check general count change
INITIAL_COUNT=$(cat /tmp/initial_campaign_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_campaign WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# Check if app is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Escape strings for JSON
NAME_ESCAPED=$(echo "$NAME" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/ /g')
DESC_ESCAPED=$(echo "$DESC" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/ /g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_exists": $([ "$RECORD_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "record_data": {
        "value": "$TARGET_KEY",
        "name": "$NAME_ESCAPED",
        "description": "$DESC_ESCAPED",
        "start_date": "$START_DATE",
        "end_date": "$END_DATE",
        "costs": $COSTS,
        "created_epoch": $CREATED_EPOCH,
        "created_by": "$CREATED_BY"
    },
    "counts": {
        "initial": $INITIAL_COUNT,
        "final": $FINAL_COUNT
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="