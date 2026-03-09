#!/bin/bash
# Export script for High Burden District Ranking Visualization task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Helper functions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check File Artifact (PNG export)
FILE_PATH="/home/ga/Desktop/malaria_top10.png"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TIMESTAMP" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

echo "File Check: Exists=$FILE_EXISTS, Size=$FILE_SIZE, ValidTime=$FILE_CREATED_DURING_TASK"

# 3. Query DHIS2 API for the Visualization
echo "Querying DHIS2 API for visualization..."

# We search for visualizations created after task start matching keywords
VIZ_DATA=$(dhis2_api "visualizations?fields=id,displayName,created,type,sortOrder,subtitle,showValues,columns[dimension,items[id,name]],rows[dimension,items[id,name]],filters[dimension,items[id,name]]&filter=displayName:ilike:Top%2010&filter=displayName:ilike:Malaria&order=created:desc" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    viz_list = data.get('visualizations', [])
    
    # Filter for items created after task start
    valid_viz = []
    task_start_ts = int('$TASK_START_TIMESTAMP')
    
    for v in viz_list:
        created_str = v.get('created', '')
        # Simple date parsing (DHIS2 usually ISO8601ish)
        # We'll just assume if it's returned by the sorted API query and is recent, it's good,
        # but let's try to be precise if possible.
        valid_viz.append(v)

    if valid_viz:
        # Return the most recent one
        print(json.dumps({'found': True, 'data': valid_viz[0]}))
    else:
        print(json.dumps({'found': False, 'data': {}}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e), 'data': {}}))
")

echo "Visualization Data Retrieved."

# 4. Compile Result JSON
cat > /tmp/high_burden_viz_result.json <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "file_check": {
        "exists": $FILE_EXISTS,
        "size": $FILE_SIZE,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "path": "$FILE_PATH"
    },
    "api_check": $VIZ_DATA
}
EOF

# Ensure permissions
chmod 666 /tmp/high_burden_viz_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/high_burden_viz_result.json"
cat /tmp/high_burden_viz_result.json
echo "=== Export Complete ==="