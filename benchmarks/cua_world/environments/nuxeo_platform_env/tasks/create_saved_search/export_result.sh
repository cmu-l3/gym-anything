#!/bin/bash
# Export script for create_saved_search task
# Queries Nuxeo API for the created saved search and exports details for verification.

set -e
echo "=== Exporting create_saved_search result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 3. Query Nuxeo API for the Saved Search document
# We look for a SavedSearch document with the exact title
echo "Querying API for SavedSearch..."
API_RESPONSE=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+SavedSearch+WHERE+dc:title='Project+Reports+Search'+AND+ecm:isTrashed=0")

# 4. Extract details using Python
# We need to extract: existence, creation time, and the internal query/parameters
RESULT_JSON=$(echo "$API_RESPONSE" | python3 -c "
import sys, json, datetime

task_start = int($TASK_START)
try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    
    found = False
    details = {}
    
    # Iterate through entries to find one created AFTER task start
    for entry in entries:
        props = entry.get('properties', {})
        created_str = props.get('dc:created', '')
        
        # Check timestamp
        is_new = False
        if created_str:
            # Simple ISO parsing (remove Z for compatibility if needed)
            dt_str = created_str.replace('Z', '+00:00')
            try:
                dt = datetime.datetime.fromisoformat(dt_str)
                ts = dt.timestamp()
                if ts >= (task_start - 10): # 10s buffer
                    is_new = True
            except:
                pass
        
        if is_new:
            found = True
            details = entry
            break
            
    # If not found new one, take the first one found (verifier will penalize if old)
    if not found and entries:
        details = entries[0]
        found = True

    output = {
        'found': found,
        'count': len(entries),
        'document': details,
        'task_start': task_start,
        'timestamp_check': is_new if found else False
    }
    print(json.dumps(output))
    
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e), 'task_start': task_start}))
")

# 5. Check if search returns expected results (Simulation)
# If we found a saved search, let's try to see if a simple search for 'Report' works as expected
# This helps the verifier confirm the environment state wasn't broken
CONTROL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+dc:title+LIKE+'%25Report%25'+AND+ecm:isTrashed=0")
CONTROL_COUNT=$(echo "$CONTROL_SEARCH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('resultsCount', 0))" 2>/dev/null || echo "0")

# 6. Compose final JSON
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "saved_search_data": $RESULT_JSON,
    "control_search_count": $CONTROL_COUNT,
    "app_running": true
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="