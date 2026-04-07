#!/bin/bash
echo "=== Exporting Conditional Room Booking Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (Visual Evidence)
take_screenshot /tmp/task_final.png

# 2. Read Ground Truth (from setup)
if [ -f /tmp/task_ground_truth.json ]; then
    GROUND_TRUTH=$(cat /tmp/task_ground_truth.json)
else
    # Fallback if file missing (should not happen)
    GROUND_TRUTH='{"target_date": "unknown", "scenario_blocked": false, "expected_location": "unknown"}'
fi

# 3. Query Odoo for the Agent's Created Event
# We look for "Project Sync"
PYTHON_EXPORT_SCRIPT=$(cat << 'END_PYTHON'
import xmlrpc.client
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
pwd = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for the event created by the agent
    # We sort by create_date desc to get the most recent one if multiple exist
    events = models.execute_kw(db, uid, pwd, 'calendar.event', 'search_read',
        [[['name', 'ilike', 'Project Sync']]],
        {'fields': ['name', 'start', 'stop', 'location', 'create_date'], 
         'limit': 1, 
         'order': 'create_date desc'})

    result = {}
    if events:
        evt = events[0]
        result = {
            "found": True,
            "name": evt.get('name'),
            "start": evt.get('start'),  # UTC string
            "stop": evt.get('stop'),
            "location": evt.get('location') or "",
            "create_date": evt.get('create_date')
        }
    else:
        result = {
            "found": False,
            "error": "Event 'Project Sync' not found"
        }

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))

END_PYTHON
)

AGENT_RESULT=$(python3 -c "$PYTHON_EXPORT_SCRIPT")

# 4. Combine into Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ground_truth": $GROUND_TRUTH,
    "agent_result": $AGENT_RESULT,
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to Standard Location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="