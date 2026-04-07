#!/bin/bash
echo "=== Exporting cleanup_duplicate_event results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to check database state against setup info
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    # Load setup info
    if not os.path.exists('/tmp/task_setup_info.json'):
        print("Error: Setup info file missing")
        sys.exit(0) # Fail gracefully in the JSON output

    with open('/tmp/task_setup_info.json', 'r') as f:
        setup_info = json.load(f)

    good_id = setup_info['good_event_id']
    bad_id = setup_info['bad_event_id']

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check Good Event
    # read() returns list of dicts if exists, empty list if deleted
    good_data = models.execute_kw(db, uid, password, 'calendar.event', 'read', [[good_id], ['partner_ids', 'active']])
    good_exists = len(good_data) > 0
    good_attendee_count = 0
    if good_exists:
        # partner_ids is typically [id1, id2, ...]. 
        # Note: In some Odoo versions read returns IDs.
        good_attendee_count = len(good_data[0].get('partner_ids', []))

    # Check Bad Event
    bad_data = models.execute_kw(db, uid, password, 'calendar.event', 'read', [[bad_id], ['active']])
    bad_exists = len(bad_data) > 0
    
    # Check global count of 'Vendor Evaluation' events
    total_count = models.execute_kw(db, uid, password, 'calendar.event', 'search_count', [[['name', '=', 'Vendor Evaluation']]])

    # Prepare result
    result = {
        "good_event_exists": good_exists,
        "bad_event_exists": bad_exists,
        "good_event_attendee_count": good_attendee_count,
        "total_event_count": total_count,
        "task_setup_valid": True
    }

    # Write result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
        
    print("Export successful")

except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write error state
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({"error": str(e), "task_setup_valid": False}, f)
PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="