#!/bin/bash
# Export results for "create_custom_request_view" task

echo "=== Exporting Custom View Results ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot (Visual evidence of the view being active)
take_screenshot /tmp/task_final.png

# 2. Query the Database for the View Definition
# We need to find the view and its criteria
# Note: Table names and columns are best-effort based on standard SDP schemas. 
# We fetch widely to capture relevant data.

VIEW_NAME="Critical Unassigned Triage"

# Get View ID and Configuration
echo "Querying ViewConfiguration..."
VIEW_CONFIG_RAW=$(sdp_db_exec "SELECT * FROM ViewConfiguration WHERE VIEWNAME = '$VIEW_NAME'")
VIEW_ID=$(echo "$VIEW_CONFIG_RAW" | cut -d'|' -f1 | head -n1) # Assuming first column is usually ID

# Get Criteria for this View
VIEW_CRITERIA_RAW=""
if [ -n "$VIEW_ID" ] && [ "$VIEW_ID" != "" ]; then
    echo "Found View ID: $VIEW_ID"
    echo "Querying ViewCriteria..."
    # Columns in ViewCriteria are typically: CRITERIAID, VIEWID, COLUMNNAME, COMPARATOR, VALUE, etc.
    VIEW_CRITERIA_RAW=$(sdp_db_exec "SELECT * FROM ViewCriteria WHERE VIEWID = $VIEW_ID")
else
    echo "View ID not found."
fi

# 3. Check if app is running
APP_RUNNING=$(pgrep -f "java.*WrapperSimpleApp" > /dev/null && echo "true" || echo "false")

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Python script to safely construct JSON with escaping
python3 -c "
import json
import sys

try:
    view_config = sys.argv[1]
    view_criteria = sys.argv[2]
    task_start = int(sys.argv[3])
    task_end = int(sys.argv[4])
    app_running = sys.argv[5] == 'true'
    
    # Simple parsing of raw DB output (pipe separated is common in psql -A -t)
    # We just store the raw string for the verifier to regex check, 
    # as column ordering varies by version.
    
    result = {
        'task_start': task_start,
        'task_end': task_end,
        'app_was_running': app_running,
        'view_found': bool(view_config and len(view_config.strip()) > 0),
        'view_config_raw': view_config,
        'view_criteria_raw': view_criteria,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" "$VIEW_CONFIG_RAW" "$VIEW_CRITERIA_RAW" "$TASK_START" "$TASK_END" "$APP_RUNNING" > "$TEMP_JSON"

# 5. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result data:"
cat /tmp/task_result.json
echo "=== Export complete ==="