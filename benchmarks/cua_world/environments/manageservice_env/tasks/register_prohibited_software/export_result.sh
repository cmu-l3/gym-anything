#!/bin/bash
echo "=== Exporting Register Prohibited Software results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to run SQL and format as JSON array
# We fetch: SoftwareName, TypeName, ManufacturerName, CreatedTime (if available)
echo "Querying Software List..."
SOFTWARE_JSON=$(sdp_db_exec "
    SELECT json_agg(t) FROM (
        SELECT 
            sl.softwarename as name, 
            st.typename as type, 
            m.manufacturername as manufacturer,
            sl.softwareversion as version
        FROM softwarelist sl 
        LEFT JOIN softwaretype st ON sl.softwaretypeid = st.softwaretypeid 
        LEFT JOIN manufacturer m ON sl.manufacturerid = m.manufacturerid
        WHERE sl.softwarename IN ('uTorrent', 'Steam')
    ) t;
")

# If json_agg is not available (older PG), we might get empty or raw text. 
# Fallback logic isn't complex here, assuming SDP uses a modern enough PG or we parse raw.
# But for robustness, let's just save the raw output if JSON fails.
if [ -z "$SOFTWARE_JSON" ]; then
    SOFTWARE_JSON="[]"
fi

# Check Notification Rules
# Look for rules related to prohibited software
echo "Querying Notification Rules..."
NOTIFICATION_STATUS=$(sdp_db_exec "
    SELECT status 
    FROM notificationrules 
    WHERE rulename ILIKE '%prohibited%' 
    LIMIT 1;
")

# If null (no rule found), default to false
if [ -z "$NOTIFICATION_STATUS" ]; then
    NOTIFICATION_STATUS="false"
fi

# Initial count for comparison
INITIAL_COUNT=$(cat /tmp/initial_prohibited_count.txt 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "software_found": $SOFTWARE_JSON,
    "notification_enabled": "$NOTIFICATION_STATUS",
    "initial_prohibited_count": $INITIAL_COUNT,
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