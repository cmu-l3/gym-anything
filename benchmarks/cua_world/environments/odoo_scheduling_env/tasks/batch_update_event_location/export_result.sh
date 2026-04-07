#!/bin/bash
echo "=== Exporting batch_update_event_location results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Python verification script inside container to query Odoo
# This script compares current state against the baseline recorded in setup
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'
baseline_file = '/tmp/batch_location_baseline.json'
output_file = '/tmp/task_result.json'

target_new_location = "Executive Conference Room - 3rd Floor"

result = {
    "baseline_found": False,
    "error": None,
    "remaining_board_room_count": 0,
    "target_updates": {},
    "total_count_changed": False,
    "collateral_damage": [],
    "data_preserved": True
}

try:
    if not os.path.exists(baseline_file):
        result["error"] = "Baseline file not found"
        print(json.dumps(result))
        sys.exit(0)
    
    with open(baseline_file, 'r') as f:
        baseline = json.load(f)
    
    result["baseline_found"] = True
    
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # CHECK 1: Are there any events left with "Board Room"?
    remaining = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', 
        [[['location', '=', 'Board Room']]])
    result["remaining_board_room_count"] = remaining

    # CHECK 2: Did the specific target events get updated correctly?
    # We use the IDs from the baseline to be precise
    target_ids = baseline['board_room_ids']
    current_targets = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[['id', 'in', target_ids]]],
        {'fields': ['id', 'name', 'location', 'start', 'stop', 'partner_ids']})
    
    for event in current_targets:
        is_correct = (event['location'] or "").strip() == target_new_location
        result["target_updates"][event['name']] = {
            "location": event['location'],
            "correct": is_correct
        }
        
        # Check data preservation (dates/attendees shouldn't change)
        # Find original in baseline
        orig = next((e for e in baseline['board_room_events'] if e['id'] == event['id']), None)
        if orig:
            if event['start'] != orig['start'] or event['stop'] != orig['stop'] or \
               set(event['partner_ids']) != set(orig['partner_ids']):
                result["data_preserved"] = False

    # CHECK 3: Did total count change? (Anti-gaming: delete/recreate)
    current_total = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[]])
    result["total_count_changed"] = (current_total != baseline['total_event_count'])
    result["count_diff"] = current_total - baseline['total_event_count']

    # CHECK 4: Collateral damage (other events changing location)
    # We check a sample or all other events
    all_current = models.execute_kw(db, uid, password, 'calendar.event', 'search_read',
        [[]], {'fields': ['id', 'name', 'location']})
    
    baseline_snapshot = baseline['all_events_snapshot'] # Dict by ID
    
    for event in all_current:
        eid = str(event['id'])
        # Skip our targets
        if int(eid) in target_ids:
            continue
            
        if eid in baseline_snapshot:
            orig_loc = baseline_snapshot[eid]['location'] or ""
            curr_loc = event['location'] or ""
            if orig_loc != curr_loc:
                result["collateral_damage"].append({
                    "id": eid,
                    "name": event['name'],
                    "old": orig_loc,
                    "new": curr_loc
                })

except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Handle permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true