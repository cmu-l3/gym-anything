#!/bin/bash
set -e
echo "=== Exporting task results: create_cid_group_container ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Query Database for the Container
echo "Querying Vicidial database..."

# Use a temporary file for the SQL query result to handle newlines/special chars safely
TEMP_SQL_RESULT=$(mktemp)

# Query strictly for the specific container ID
docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
    "SELECT container_id, container_notes, container_type, container_entry 
     FROM vicidial_settings_containers 
     WHERE container_id='CID_EAST_COAST' 
     LIMIT 1;" > "$TEMP_SQL_RESULT" 2>/dev/null || true

# Read results
if [ -s "$TEMP_SQL_RESULT" ]; then
    CONTAINER_EXISTS="true"
    # Read fields (tab separated by default in mysql -N)
    # We use python to safely escape and format to JSON to avoid bash string parsing hell
    python3 -c "
import sys
import json
import csv

try:
    with open('$TEMP_SQL_RESULT', 'r') as f:
        reader = csv.reader(f, delimiter='\t')
        row = next(reader)
        data = {
            'container_id': row[0],
            'container_notes': row[1],
            'container_type': row[2],
            'container_entry': row[3]
        }
        print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/container_data.json
else
    CONTAINER_EXISTS="false"
    echo "{}" > /tmp/container_data.json
fi

rm -f "$TEMP_SQL_RESULT"

# Check if application was running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Combine into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "container_exists": $CONTAINER_EXISTS,
    "container_data": $(cat /tmp/container_data.json),
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="