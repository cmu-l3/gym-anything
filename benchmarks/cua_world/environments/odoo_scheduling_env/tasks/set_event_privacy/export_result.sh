#!/bin/bash
echo "=== Exporting set_event_privacy results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the final state of the event
python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result_data = {
    "event_found": False,
    "privacy": None,
    "show_as": None,
    "write_date": None,
    "name": None,
    "start": None,
    "stop": None,
    "baseline_write_date": None,
    "baseline_name": None,
    "baseline_start": None,
    "baseline_stop": None
}

try:
    # Load baseline
    if os.path.exists('/tmp/task_baseline.json'):
        with open('/tmp/task_baseline.json', 'r') as f:
            baseline = json.load(f)
            result_data["baseline_write_date"] = baseline.get("initial_write_date")
            result_data["baseline_name"] = baseline.get("initial_name")
            result_data["baseline_start"] = baseline.get("initial_start")
            result_data["baseline_stop"] = baseline.get("initial_stop")
            event_id = baseline.get("event_id")
    else:
        # Fallback if baseline missing (shouldn't happen)
        event_id = None

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    if event_id:
        events = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [event_id], 
            {'fields': ['id', 'name', 'privacy', 'show_as', 'write_date', 'start', 'stop']})
        
        if events:
            ev = events[0]
            result_data["event_found"] = True
            result_data["privacy"] = ev.get('privacy')
            result_data["show_as"] = ev.get('show_as')
            result_data["write_date"] = ev.get('write_date')
            result_data["name"] = ev.get('name')
            result_data["start"] = ev.get('start')
            result_data["stop"] = ev.get('stop')
        else:
            print("Event ID found in baseline but not in DB anymore")
    else:
        # Try to find by name if baseline failed
        events = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
            [[['name', '=', 'Investor Update Preparation']]],
            {'fields': ['id', 'name', 'privacy', 'show_as', 'write_date', 'start', 'stop']})
        if events:
            ev = events[0]
            result_data["event_found"] = True
            result_data["privacy"] = ev.get('privacy')
            result_data["show_as"] = ev.get('show_as')
            result_data["write_date"] = ev.get('write_date')
            result_data["name"] = ev.get('name')
            result_data["start"] = ev.get('start')
            result_data["stop"] = ev.get('stop')

except Exception as e:
    result_data["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYTHON_EOF

# Set permissions so it can be copied out
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="