#!/bin/bash
echo "=== Exporting duplicate_and_modify_event result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to extract verification data from Odoo
# We fetch both the original Q2 event (to check preservation) and the new Q3 event
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os
from datetime import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
output_file = '/tmp/task_result.json'

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Fetch Q3 Financial Review (The target event)
    # We search specifically for the name
    q3_events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
        [[['name', '=', 'Q3 Financial Review']]],
        {'fields': ['id', 'name', 'start', 'stop', 'location', 'description', 'partner_ids', 'create_date', 'write_date']})
    
    q3_data = None
    q3_attendees = []
    
    if q3_events:
        # Take the most recently created one if duplicates exist
        q3_data = sorted(q3_events, key=lambda x: x['id'], reverse=True)[0]
        
        # Resolve attendee names for Q3
        if q3_data.get('partner_ids'):
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'search_read',
                [[['id', 'in', q3_data['partner_ids']]]],
                {'fields': ['name']})
            q3_attendees = [p['name'] for p in partners]

    # 2. Fetch Q2 Financial Review (The base event)
    q2_events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
        [[['name', '=', 'Q2 Financial Review']]],
        {'fields': ['id', 'name', 'start', 'stop', 'location', 'description', 'partner_ids', 'write_date']})
    
    q2_data = q2_events[0] if q2_events else None
    
    # 3. Load Initial Baseline for Q2 (captured in setup)
    q2_baseline = {}
    if os.path.exists('/tmp/q2_baseline.json'):
        with open('/tmp/q2_baseline.json', 'r') as f:
            q2_baseline = json.load(f)

    # 4. Get counts
    event_count = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_count', [[]])
    
    # 5. Build Result Dictionary
    result = {
        "q3_found": bool(q3_data),
        "q3_event": q3_data,
        "q3_attendee_names": q3_attendees,
        "q2_event": q2_data,
        "q2_baseline": q2_baseline,
        "final_event_count": event_count,
        "task_start_ts": int(os.environ.get('TASK_START', 0)),
        "task_end_ts": int(os.environ.get('TASK_END', 0)),
        "timestamp": datetime.now().isoformat()
    }

    # Save to file
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
        
    print(f"Export successful. Q3 Found: {bool(q3_data)}")

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Save partial error result
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="