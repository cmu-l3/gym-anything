#!/bin/bash
# Export script for "resolve_close_request" task

echo "=== Exporting Resolve/Close Request results ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Get task info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REQUEST_ID=$(cat /tmp/task_request_id.txt 2>/dev/null || echo "0")

if [ "$REQUEST_ID" == "0" ]; then
    # Try to find ID by title if missing
    REQUEST_ID=$(sdp_db_exec "SELECT workorderid FROM workorder WHERE title = 'Network connectivity down on 3rd floor' ORDER BY workorderid DESC LIMIT 1;")
fi

echo "Verifying Request ID: $REQUEST_ID"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Verification Data

# Query Status
# Schema note: workorder -> workorderstates -> statusdefinition
STATUS_NAME=$(sdp_db_exec "
    SELECT s.statusname 
    FROM workorder w 
    JOIN workorderstates ws ON w.workorderid = ws.workorderid 
    JOIN statusdefinition s ON ws.statusid = s.statusid 
    WHERE w.workorderid = $REQUEST_ID;")

# Query Resolution
# Schema note: workorder -> workorderresolution
RESOLUTION_TEXT=$(sdp_db_exec "
    SELECT r.resolution 
    FROM workorderresolution r 
    WHERE r.workorderid = $REQUEST_ID;")

# Query Time Spent (Worklog)
# Schema note: worklog table links to workorderid. timespent is usually in minutes or milliseconds.
# Assuming minutes (standard for SDP DB dumps, but could be ms).
# We sum up all worklogs for this ticket created after task start.
TOTAL_TIME_SPENT=$(sdp_db_exec "
    SELECT COALESCE(SUM(timespent), 0) 
    FROM worklog 
    WHERE workorderid = $REQUEST_ID;")
    
# Check modification time of resolution (Anti-gaming)
# If last_updated or equivalent column exists
RESOLUTION_TIME=$(sdp_db_exec "
    SELECT last_updated 
    FROM workorderresolution 
    WHERE workorderid = $REQUEST_ID;")
    
# If resolution time is empty/null, use current time if resolution exists
if [ -n "$RESOLUTION_TEXT" ] && [ -z "$RESOLUTION_TIME" ]; then
    RESOLUTION_TIME=$(date +%s000) # Fallback
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "request_id": "$REQUEST_ID",
    "final_status": "$STATUS_NAME",
    "resolution_text": $(echo "$RESOLUTION_TEXT" | jq -R .),
    "total_time_spent_minutes": "$TOTAL_TIME_SPENT",
    "resolution_timestamp": "$RESOLUTION_TIME",
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