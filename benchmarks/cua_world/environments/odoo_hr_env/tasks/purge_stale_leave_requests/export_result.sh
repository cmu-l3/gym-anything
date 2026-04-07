#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to check the status of the specific IDs we created
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import os

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

output_file = '/tmp/task_result.json'
scenario_file = '/tmp/scenario_data.json'

try:
    if not os.path.exists(scenario_file):
        print("Error: Scenario data file not found", file=sys.stderr)
        result = {"error": "setup_failed"}
    else:
        with open(scenario_file, 'r') as f:
            scenario = json.load(f)

        common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        uid = common.authenticate(db, username, password, {})
        models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

        def check_ids_exist(id_list):
            if not id_list:
                return []
            # 'read' returns a list of dicts for found records. 
            # If a record is deleted, it won't be in the returned list.
            try:
                # We search for these IDs to see which ones still exist
                found_records = models.execute_kw(db, uid, password, 'hr.leave', 'read', [id_list], {'fields': ['id']})
                found_ids = [r['id'] for r in found_records]
                return found_ids
            except Exception as e:
                print(f"Error reading records: {e}")
                return []

        # Check Stale Drafts (Should be deleted)
        stale_remaining = check_ids_exist(scenario.get("stale_draft_ids", []))
        
        # Check Future Drafts (Should exist)
        future_draft_remaining = check_ids_exist(scenario.get("future_draft_ids", []))
        
        # Check Past Confirmed (Should exist)
        past_confirmed_remaining = check_ids_exist(scenario.get("past_confirmed_ids", []))
        
        # Check Future Confirmed (Should exist)
        future_confirmed_remaining = check_ids_exist(scenario.get("future_confirmed_ids", []))
        
        # Get total count of leaves for general stat
        total_count = models.execute_kw(db, uid, password, 'hr.leave', 'search_count', [[]])

        result = {
            "scenario": scenario,
            "results": {
                "stale_remaining_ids": stale_remaining,
                "future_draft_remaining_ids": future_draft_remaining,
                "past_confirmed_remaining_ids": past_confirmed_remaining,
                "future_confirmed_remaining_ids": future_confirmed_remaining,
                "total_db_count": total_count
            },
            "task_start": int(os.environ.get('TASK_START', 0)),
            "task_end": int(os.environ.get('TASK_END', 0))
        }

    with open(output_file, 'w') as f:
        json.dump(result, f)
    
    print("Export successful.")
    
except Exception as e:
    print(f"Export failed: {e}", file=sys.stderr)
    # Write failure result
    with open(output_file, 'w') as f:
        json.dump({"error": str(e)}, f)
PYTHON_EOF

# Set permissions so ga user can read it if needed (though we copy out as root usually)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="