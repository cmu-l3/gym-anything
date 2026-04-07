#!/bin/bash
echo "=== Exporting schedule_back_to_back_meetings result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read configuration
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")
TARGET_DATE=$(cat /tmp/target_date.txt 2>/dev/null || echo "")

echo "Verifying events for date: $TARGET_DATE"

# Use Python/XML-RPC to inspect the database thoroughly
# We do the heavy lifting here inside the container where we have direct DB access
python3 << PYEOF
import xmlrpc.client
import json
import sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
target_date = '$TARGET_DATE'
task_start_ts = int($TASK_START_TIME)

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch all events created after task start
    # We filter in Python to handle the timestamp comparison robustly
    fields = ['id', 'name', 'start', 'stop', 'location', 'partner_ids', 'create_date']
    all_events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
                                  [[]], {'fields': fields})

    # Filter for events created during the task
    # create_date is usually UTC string "YYYY-MM-DD HH:MM:SS"
    created_events = []
    for evt in all_events:
        cdate_str = evt.get('create_date')
        if cdate_str:
            cdate_dt = datetime.strptime(cdate_str, '%Y-%m-%d %H:%M:%S')
            # Simple check: if create_date is recent (after task start)
            # Adjusting for potential timezone offsets in Odoo (usually UTC)
            # vs system time. Using a generous buffer or comparing vs system time.
            # Best approach: Odoo create_date is UTC. System time is UTC.
            if cdate_dt.timestamp() > task_start_ts:
                created_events.append(evt)
    
    # If standard timestamp check fails (due to clock skew), fall back to name search
    if not created_events:
        print("Timestamp check yielded 0 events, searching by name...")
        created_events = [e for e in all_events if e['name'] in ['Sprint Review', 'Executive Briefing']]

    # Identify our specific target events
    sprint_review = None
    exec_briefing = None

    for evt in created_events:
        name = evt.get('name', '')
        if 'Sprint Review' in name:
            sprint_review = evt
        elif 'Executive Briefing' in name:
            exec_briefing = evt

    # Analyze Sprint Review
    sr_data = {}
    if sprint_review:
        sr_data['exists'] = True
        sr_data['name'] = sprint_review['name']
        sr_data['location'] = sprint_review['location']
        sr_data['start'] = sprint_review['start']
        sr_data['stop'] = sprint_review['stop']
        
        # Check attendees
        pids = sprint_review.get('partner_ids', [])
        partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [pids], {'fields': ['name']})
        sr_data['attendees'] = [p['name'] for p in partners]
    else:
        sr_data['exists'] = False

    # Analyze Executive Briefing
    eb_data = {}
    if exec_briefing:
        eb_data['exists'] = True
        eb_data['name'] = exec_briefing['name']
        eb_data['location'] = exec_briefing['location']
        eb_data['start'] = exec_briefing['start']
        eb_data['stop'] = exec_briefing['stop']
        
        pids = exec_briefing.get('partner_ids', [])
        partners = models.execute_kw(db, uid, password, 'res.partner', 'read', [pids], {'fields': ['name']})
        eb_data['attendees'] = [p['name'] for p in partners]
    else:
        eb_data['exists'] = False

    # Calculate global stats
    final_count = len(all_events)
    
    result = {
        'target_date': target_date,
        'sprint_review': sr_data,
        'executive_briefing': eb_data,
        'initial_count': int('$INITIAL_COUNT'),
        'final_count': final_count,
        'created_event_count': len(created_events),
        'timestamp': datetime.now().isoformat()
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("Export successful.")

except Exception as e:
    print(f"Error exporting results: {e}", file=sys.stderr)
    # Write partial error result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
PYEOF

echo "Result saved to /tmp/task_result.json"
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="