#!/bin/bash
set -e
echo "=== Exporting add_request_tasks result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REQUEST_ID=$(cat /tmp/parent_request_id.txt 2>/dev/null | tr -d '[:space:]')
INITIAL_COUNT=$(cat /tmp/initial_task_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare result JSON components
TASKS_JSON="[]"
REQUEST_FOUND="false"

if [ -n "$REQUEST_ID" ] && [ "$REQUEST_ID" != "UNKNOWN" ]; then
    REQUEST_FOUND="true"
    
    # Query tasks associated with this request
    # We select ID, Title, Description, and Creation Time
    # Note: SDP stores time in milliseconds
    
    # Using a separator unlikely to be in user text, e.g., |~|
    TASKS_RAW=$(sdp_db_exec "
        SELECT 
            td.TASKID || '|~|' || 
            COALESCE(td.TITLE, '') || '|~|' || 
            COALESCE(td.DESCRIPTION, '') || '|~|' || 
            COALESCE(td.CREATEDTIME, 0)
        FROM taskdetails td 
        JOIN workordertotask wt ON td.TASKID = wt.TASKID 
        WHERE wt.WORKORDERID = ${REQUEST_ID} 
        ORDER BY td.TASKID ASC;
    " 2>/dev/null)
    
    # Convert raw SQL output to JSON array
    # This loop handles the multi-line output from psql
    TASKS_JSON="["
    FIRST=true
    
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        # Split by separator
        ID=$(echo "$line" | awk -F'|~|' '{print $1}')
        TITLE=$(echo "$line" | awk -F'|~|' '{print $2}' | sed 's/"/\\"/g')
        DESC=$(echo "$line" | awk -F'|~|' '{print $3}' | sed 's/"/\\"/g' | tr -d '\n\r')
        TIME=$(echo "$line" | awk -F'|~|' '{print $4}')
        
        if [ "$FIRST" = "true" ]; then
            FIRST=false
        else
            TASKS_JSON="${TASKS_JSON},"
        fi
        
        TASKS_JSON="${TASKS_JSON}{\"id\": \"$ID\", \"title\": \"$TITLE\", \"description\": \"$DESC\", \"created_time\": $TIME}"
        
    done <<< "$TASKS_RAW"
    
    TASKS_JSON="${TASKS_JSON}]"
else
    # Fallback if ID was lost, try finding by title again
    TASKS_JSON="[]" 
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "java" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "parent_request_id": "$REQUEST_ID",
    "request_found": $REQUEST_FOUND,
    "initial_task_count": $INITIAL_COUNT,
    "tasks": $TASKS_JSON,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="