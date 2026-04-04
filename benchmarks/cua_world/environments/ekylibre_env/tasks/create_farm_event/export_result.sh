#!/bin/bash
set -e
echo "=== Exporting create_farm_event result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initial count
INITIAL_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")

# Search for the specific event
# We look for the most recently created event that matches the name pattern
# Using a broad ILIKE to find partial matches for partial credit
EVENT_JSON=$(ekylibre_db_query "
    SELECT row_to_json(t) FROM (
        SELECT 
            name, 
            place, 
            description, 
            nature,
            to_char(started_at, 'YYYY-MM-DD HH24:MI:SS') as started_at_str,
            to_char(stopped_at, 'YYYY-MM-DD HH24:MI:SS') as stopped_at_str,
            EXTRACT(EPOCH FROM created_at)::INTEGER as created_at_epoch
        FROM events 
        WHERE name ILIKE '%Audit%' OR name ILIKE '%certification%'
        ORDER BY created_at DESC 
        LIMIT 1
    ) t;" 2>/dev/null || echo "")

# If no specific match found, get the absolute latest event to check for generic creation
if [ -z "$EVENT_JSON" ]; then
    LATEST_EVENT_JSON=$(ekylibre_db_query "
        SELECT row_to_json(t) FROM (
            SELECT 
                name, 
                place, 
                description, 
                nature,
                to_char(started_at, 'YYYY-MM-DD HH24:MI:SS') as started_at_str,
                to_char(stopped_at, 'YYYY-MM-DD HH24:MI:SS') as stopped_at_str,
                EXTRACT(EPOCH FROM created_at)::INTEGER as created_at_epoch
            FROM events 
            ORDER BY created_at DESC 
            LIMIT 1
        ) t;" 2>/dev/null || echo "")
else
    LATEST_EVENT_JSON="$EVENT_JSON"
fi

# Prepare result JSON
# Use a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "found_event": ${EVENT_JSON:-null},
    "latest_event": ${LATEST_EVENT_JSON:-null},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="