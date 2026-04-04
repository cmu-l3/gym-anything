#!/bin/bash
echo "=== Exporting Configure Provider Schedule Result ==="

source /workspace/scripts/task_utils.sh

# Get Dr. Strange ID
STRANGE_ID=$(cat /tmp/dr_strange_id.txt 2>/dev/null)
if [ -z "$STRANGE_ID" ]; then
    STRANGE_ID=$(librehealth_query "SELECT id FROM users WHERE username='dr_strange'")
fi

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture Final Screenshot
take_screenshot /tmp/task_final.png

# Query the Calendar Events table for this user
# We fetch: Event ID, Start Time, End Time, Category Name, Recurrence Type, Recurrence Spec, Creation Date/Time (if avail)
# Note: openemr_postcalendar_events structure:
# pc_eid (id), pc_aid (agent/user id), pc_title, pc_time (timestamp), pc_startTime, pc_endTime, pc_recurrtype, pc_recurrspec, pc_catid
# We join with categories to get the category name

echo "Querying database for events..."

# Create a temporary SQL script to output JSON-like structure or CSV
# We will use python to format the SQL output into JSON safely
cat > /tmp/export_events.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(sql):
    cmd = ["docker", "exec", "librehealth-db", "mysql", "-u", "libreehr", "-ps3cret", "libreehr", "-N", "-e", sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

aid = sys.argv[1]
if not aid:
    print(json.dumps([]))
    sys.exit(0)

# Fetch raw rows
sql = f"""
SELECT 
    e.pc_eid, 
    e.pc_startTime, 
    e.pc_endTime, 
    e.pc_recurrtype, 
    e.pc_recurrspec, 
    e.pc_catid, 
    c.pc_category,
    e.pc_eventDate
FROM openemr_postcalendar_events e
LEFT JOIN openemr_postcalendar_categories c ON e.pc_catid = c.pc_catid
WHERE e.pc_aid = {aid}
"""

raw_data = run_query(sql)
events = []

if raw_data:
    for line in raw_data.split('\n'):
        if not line.strip(): continue
        parts = line.split('\t')
        if len(parts) >= 7:
            events.append({
                "eid": parts[0],
                "startTime": parts[1],
                "endTime": parts[2],
                "recurrType": parts[3],
                "recurrSpec": parts[4],
                "catId": parts[5],
                "category": parts[6],
                "eventDate": parts[7] if len(parts) > 7 else ""
            })

print(json.dumps(events))
PYEOF

# Run the python script to get events JSON
EVENTS_JSON=$(python3 /tmp/export_events.py "$STRANGE_ID")

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dr_strange_id": "$STRANGE_ID",
    "events": $EVENTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="