#!/bin/bash
# Export script for TB Treatment Notification Config task

echo "=== Exporting TB Notification Result ==="

source /workspace/scripts/task_utils.sh

# Inline fallback
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying new program notification templates..."

# We fetch all templates and filter in python to find those created after task start
# We also want to check which program they belong to.
# Note: programNotificationTemplates usually link to a program via 'program' field or implicit link.
# We'll fetch fields=* to get everything.

API_RESPONSE=$(dhis2_api "programNotificationTemplates?fields=id,name,created,notificationTrigger,relativeScheduledDays,notificationRecipient,messageTemplate,program[id,displayName]&paging=false" 2>/dev/null)

# Process with Python to filter for new items and extract relevant verification data
EXPORT_JSON=$(echo "$API_RESPONSE" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    templates = data.get('programNotificationTemplates', [])
    
    task_start_iso = '$TASK_START_ISO'
    # Simple iso parsing helper
    def parse_dt(s):
        try:
            return datetime.fromisoformat(s.replace('Z', '+00:00'))
        except:
            return datetime(2000, 1, 1) # Fallback
            
    try:
        start_dt = datetime.fromisoformat(task_start_iso.replace('Z', '+00:00'))
    except:
        start_dt = datetime(2020, 1, 1)

    # Load initial IDs
    initial_ids = set()
    try:
        with open('/tmp/initial_notification_ids', 'r') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    new_notifications = []
    
    for t in templates:
        t_id = t.get('id')
        t_created = t.get('created', '')
        
        # Check if strictly new (not in initial list) AND created after start time
        if t_id not in initial_ids:
            created_dt = parse_dt(t_created)
            if created_dt >= start_dt:
                new_notifications.append({
                    'id': t_id,
                    'name': t.get('name', ''),
                    'trigger': t.get('notificationTrigger', ''),
                    'recipient': t.get('notificationRecipient', ''),
                    'days': t.get('relativeScheduledDays', 0),
                    'message': t.get('messageTemplate', ''),
                    'program_name': t.get('program', {}).get('displayName', ''),
                    'created': t_created
                })

    result = {
        'count': len(new_notifications),
        'notifications': new_notifications,
        'task_start': task_start_iso
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'count': 0, 'notifications': []}))
")

echo "$EXPORT_JSON" > /tmp/tb_notification_result.json
chmod 666 /tmp/tb_notification_result.json

echo "Exported $(echo "$EXPORT_JSON" | grep -o '"count": [0-9]*' | head -1) new notifications."
echo "=== Export Complete ==="