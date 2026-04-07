#!/bin/bash
echo "=== Exporting convert_event_to_allday result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the final state of the event from the database
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch the event
    events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['name', 'ilike', 'Legal Contract Review']]],
        {'fields': [
            'id', 'name', 'allday', 'start', 'stop', 'start_date', 
            'location', 'partner_ids', 'write_date', 'description'
        ]})
    
    event_data = events[0] if events else None
    
    # Fetch partner names for verification
    partners = []
    if event_data and event_data.get('partner_ids'):
        partner_ids = event_data['partner_ids']
        partners_data = models.execute_kw(db, uid, password, 'res.partner', 'read',
            [partner_ids], {'fields': ['name']})
        partners = [p['name'] for p in partners_data]

    # Get task start time
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            task_start_ts = int(f.read().strip())
    except:
        task_start_ts = 0

    # Get baseline
    baseline = {}
    if os.path.exists('/tmp/task_baseline.json'):
        with open('/tmp/task_baseline.json', 'r') as f:
            baseline = json.load(f)

    result = {
        "event_found": bool(event_data),
        "event": event_data,
        "attendee_names": partners,
        "task_start_ts": task_start_ts,
        "baseline": baseline,
        "timestamp": datetime.now().isoformat()
    }

    # Save to temp file first then move
    with open('/tmp/result_temp.json', 'w') as f:
        json.dump(result, f, default=str)
    
    os.chmod('/tmp/result_temp.json', 0o666)
    os.rename('/tmp/result_temp.json', '/tmp/task_result.json')
    
    print("Export successful")
    
except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Create empty failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"event_found": False, "error": str(e)}, f)

PYTHON_EOF

echo "=== Export complete ==="