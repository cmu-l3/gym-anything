#!/bin/bash
# Export script for CHEM101 Calendar Events task

echo "=== Exporting CHEM101 Calendar Events Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Task Data
COURSE_ID=$(cat /tmp/chem101_course_id 2>/dev/null)
INITIAL_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

if [ -z "$COURSE_ID" ]; then
    # Fallback lookup
    COURSE_ID=$(canvas_query "SELECT id FROM courses WHERE LOWER(TRIM(course_code))='chem101' LIMIT 1")
fi

# Fetch current events for CHEM101
# We extract key fields: title, description, location, start/end times, and creation time
# JSON export is safer than line parsing for complex descriptions
echo "Fetching calendar events for CHEM101..."

# Create a temporary JSON file for events
EVENTS_JSON="/tmp/chem101_events.json"

if [ -n "$COURSE_ID" ]; then
    # Use python to format the SQL query result as JSON to handle special chars/newlines in descriptions
    # We query the DB via docker exec and pipe to python for JSON formatting
    
    QUERY="SELECT id, title, description, location_name, start_at, end_at, context_type, created_at, workflow_state FROM calendar_events WHERE context_id = $COURSE_ID AND context_type = 'Course' AND workflow_state = 'active' ORDER BY start_at ASC"
    
    # Raw pipe output
    RAW_DATA=$(canvas_query_headers "$QUERY")
    
    # Create Python script to parse PSQL output and jsonify
    cat > /tmp/parse_events.py << 'PYEOF'
import sys
import json
import re

# Simple parser for PSQL output (assuming standard formatting or using parsing lib if available)
# Since PSQL formatting can be tricky, we'll try to be robust or use a simpler query method in future
# For now, we will assume standard | separator and handle basic parsing
# Actually, let's use a safer approach: SQL returning JSON directly if PG supports it, 
# or manual construction. Canvas PG usually supports row_to_json.

print(json.dumps({"info": "Parsing handled in verifier using raw export"}))
PYEOF
    
    # BETTER APPROACH: Use PSQL to generate JSON directly
    # This avoids all parsing issues with newlines in descriptions
    JSON_QUERY="SELECT json_agg(t) FROM (SELECT id, title, description, location_name, start_at, end_at, context_type, created_at, workflow_state FROM calendar_events WHERE context_id = $COURSE_ID AND context_type = 'Course' AND workflow_state = 'active') t;"
    
    EVENTS_JSON_STRING=$(canvas_query "$JSON_QUERY")
else
    EVENTS_JSON_STRING="[]"
fi

# Check for "do nothing" - did the count change?
if [ -n "$COURSE_ID" ]; then
    FINAL_COUNT=$(canvas_query "SELECT COUNT(*) FROM calendar_events WHERE context_id = $COURSE_ID AND context_type = 'Course' AND workflow_state = 'active'" || echo "0")
else
    FINAL_COUNT="0"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/chem101_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": "${COURSE_ID}",
    "initial_count": ${INITIAL_COUNT},
    "final_count": ${FINAL_COUNT},
    "task_start_ts": ${TASK_START},
    "export_ts": $(date +%s),
    "events_data": ${EVENTS_JSON_STRING:-[]}
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="