#!/bin/bash
echo "=== Exporting create_mail_template results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the database for the specific Mail Template
# We use row_to_json to safely handle potential newlines in the body text
echo "--- Querying database for Mail Template ---"

# Query looks for the specific name created in the correct client
JSON_RESULT=$(idempiere_query "
SELECT row_to_json(t) 
FROM (
    SELECT 
        r_mailtext_id, 
        name, 
        mailheader, 
        mailtext, 
        isactive,
        created,
        EXTRACT(EPOCH FROM created) as created_epoch
    FROM r_mailtext 
    WHERE name='Vendor Order Inquiry' 
      AND ad_client_id=$CLIENT_ID
) t
" 2>/dev/null)

# 2. Check application state
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Construct the result JSON
# If no record found, JSON_RESULT will be empty
if [ -z "$JSON_RESULT" ]; then
    JSON_RESULT="null"
fi

# Write to temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "db_record": $JSON_RESULT
}
EOF

# Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="