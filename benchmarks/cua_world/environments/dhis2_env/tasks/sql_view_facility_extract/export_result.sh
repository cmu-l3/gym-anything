#!/bin/bash
# Export script for SQL View Facility Extract task

echo "=== Exporting SQL View Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Check Downloads
echo "Checking Downloads..."
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DOWNLOAD_INFO=$(python3 << 'PYEOF'
import os, json, time
dl_dir = "/home/ga/Downloads"
start_time = int(open("/tmp/task_start_timestamp").read().strip())
files = []
if os.path.exists(dl_dir):
    for f in os.listdir(dl_dir):
        path = os.path.join(dl_dir, f)
        if os.path.isfile(path):
            mtime = os.path.getmtime(path)
            size = os.path.getsize(path)
            if mtime > start_time:
                files.append({"name": f, "size": size, "mtime": mtime})
print(json.dumps({"count": len(files), "files": files}))
PYEOF
)
echo "Download info: $DOWNLOAD_INFO"

# 3. Check SQL View Creation via API
echo "Querying SQL Views..."
# Look for views created recently or matching the name
# Note: DHIS2 SQL Views might not store 'created' date in all versions, 
# so we rely on existence + name match since we cleaned up in setup.
SQL_VIEW_RESULT=$(dhis2_api "sqlViews?filter=displayName:ilike:Kenema&fields=id,displayName,sqlQuery,type,lastUpdated&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    views = data.get('sqlViews', [])
    result = {'found': False, 'views': []}
    
    if views:
        result['found'] = True
        for v in views:
            result['views'].append({
                'id': v.get('id'),
                'name': v.get('displayName'),
                'query': v.get('sqlQuery', ''),
                'type': v.get('type')
            })
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

echo "SQL View Search Result: $SQL_VIEW_RESULT"

# 4. Verify SQL Execution (Rows returned)
# If a view was found, try to execute it to see if it returns data
PRIMARY_VIEW_ID=$(echo "$SQL_VIEW_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['views'][0]['id']) if d.get('views') else print('')")

ROW_COUNT=0
EXECUTION_SUCCESS="false"

if [ -n "$PRIMARY_VIEW_ID" ]; then
    echo "Executing SQL View ID: $PRIMARY_VIEW_ID"
    # Try data.json endpoint which executes the view
    DATA_RESP=$(dhis2_api "sqlViews/$PRIMARY_VIEW_ID/data.json?paging=false" 2>/dev/null)
    
    # Check for rows
    ROW_COUNT=$(echo "$DATA_RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # DHIS2 SQL view data structure: {'listGrid': {'headers': [...], 'rows': [[...], ...]}}
    # or sometimes directly {'headers': ..., 'rows': ...} depending on version/endpoint
    rows = d.get('listGrid', {}).get('rows', []) or d.get('rows', [])
    print(len(rows))
except:
    print(0)
")
    if [ "$ROW_COUNT" -gt 0 ]; then
        EXECUTION_SUCCESS="true"
    fi
    echo "Execution returned $ROW_COUNT rows"
fi

# 5. Compile Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_epoch": $TASK_START_EPOCH,
    "downloads": $DOWNLOAD_INFO,
    "sql_view_search": $SQL_VIEW_RESULT,
    "execution": {
        "view_id": "$PRIMARY_VIEW_ID",
        "row_count": $ROW_COUNT,
        "success": $EXECUTION_SUCCESS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json