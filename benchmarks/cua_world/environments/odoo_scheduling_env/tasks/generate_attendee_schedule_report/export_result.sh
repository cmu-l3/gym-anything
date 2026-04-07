#!/bin/bash
echo "=== Exporting generate_attendee_schedule_report results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check Output File
OUTPUT_PATH="/home/ga/Documents/grace_patel_schedule.txt"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" | base64 -w 0)
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# 4. Fetch Ground Truth from Odoo DB
# We need to know what events Grace Patel is ACTUALLY attending.
# We use a python script to query Odoo via XML-RPC.

GROUND_TRUTH_JSON=$(python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys

url = "http://localhost:8069"
db = "odoo_scheduling"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Partner ID for Grace Patel
    partners = models.execute_kw(db, uid, password, 'res.partner', 'search',
        [[['name', '=', 'Grace Patel']]])
    
    if not partners:
        print(json.dumps({"error": "Grace Patel not found in DB", "events": []}))
        sys.exit(0)
        
    grace_id = partners[0]

    # 2. Find Events where Grace is an attendee (partner_ids contains grace_id)
    # The 'partner_ids' field is a Many2many.
    domain = [['partner_ids', 'in', [grace_id]]]
    fields = ['name', 'start', 'allday', 'location', 'description']
    
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [domain], {'fields': fields})

    print(json.dumps({"events": events}))

except Exception as e:
    print(json.dumps({"error": str(e), "events": []}))
PYTHON_EOF
)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_mtime": $FILE_MTIME,
    "output_content_b64": "$OUTPUT_CONTENT",
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"