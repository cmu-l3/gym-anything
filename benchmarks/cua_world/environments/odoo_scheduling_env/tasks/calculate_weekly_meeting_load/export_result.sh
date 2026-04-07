#!/bin/bash
echo "=== Exporting calculate_weekly_meeting_load results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check User Output File
OUTPUT_FILE="/home/ga/alice_load.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
USER_VALUE=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    # Check if created/modified after start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content, trimming whitespace
    USER_VALUE=$(cat "$OUTPUT_FILE" | tr -d '[:space:]')
fi

# 2. Calculate Ground Truth dynamically from Odoo DB
# We do this HERE inside the container so we have direct XML-RPC access
GROUND_TRUTH_JSON=$(python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import json
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

response = {
    "ground_truth_hours": 0.0,
    "anchor_found": False,
    "target_week_start": "",
    "target_week_end": "",
    "events_found": [],
    "error": None
}

try:
    # Connect
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find Anchor Event "Q2 Financial Review"
    anchor_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Financial Review']]],
        {'fields': ['start', 'stop'], 'limit': 1}
    )

    if not anchor_events:
        response["error"] = "Anchor event not found"
    else:
        response["anchor_found"] = True
        anchor_start_str = anchor_events[0]['start']  # "YYYY-MM-DD HH:MM:SS"
        anchor_dt = datetime.datetime.strptime(anchor_start_str, "%Y-%m-%d %H:%M:%S")
        
        # Calculate Week Start (Monday) and End (Sunday)
        # Odoo stores UTC, but we usually schedule in local. 
        # Assuming simple date logic (Monday 00:00 to Sunday 23:59:59)
        start_of_week = anchor_dt - datetime.timedelta(days=anchor_dt.weekday())
        start_of_week = start_of_week.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_week = start_of_week + datetime.timedelta(days=6, hours=23, minutes=59, seconds=59)
        
        response["target_week_start"] = start_of_week.strftime("%Y-%m-%d %H:%M:%S")
        response["target_week_end"] = end_of_week.strftime("%Y-%m-%d %H:%M:%S")

        # 2. Find Alice Johnson's Partner ID
        alice_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
            [[['name', '=', 'Alice Johnson']]]
        )
        
        if not alice_ids:
             response["error"] = "Alice Johnson not found"
        else:
            alice_id = alice_ids[0]

            # 3. Find all events in that range where Alice is an attendee
            # Domain: start >= week_start AND stop <= week_end (approximate, overlaps handled if strictly inside)
            # Better domain for intersection: start <= week_end AND stop >= week_start
            # But the task implies "meetings during the week". We will count meetings starting in that week.
            domain = [
                ['start', '>=', response["target_week_start"]],
                ['start', '<=', response["target_week_end"]],
                ['partner_ids', 'in', [alice_id]]
            ]
            
            events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                [domain],
                {'fields': ['name', 'duration', 'start']}
            )
            
            total_duration = 0.0
            event_list = []
            for e in events:
                total_duration += e.get('duration', 0.0)
                event_list.append(f"{e.get('name')} ({e.get('duration')}h)")
            
            response["ground_truth_hours"] = total_duration
            response["events_found"] = event_list

except Exception as e:
    response["error"] = str(e)

print(json.dumps(response))
PYTHON_EOF
)

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "user_value_raw": "$USER_VALUE",
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="