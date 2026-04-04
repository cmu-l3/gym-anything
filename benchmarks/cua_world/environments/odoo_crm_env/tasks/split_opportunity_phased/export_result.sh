#!/bin/bash
echo "=== Exporting split_opportunity_phased results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo for the current state of opportunities
python3 - <<PYEOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Define fields to fetch
    fields = ['id', 'name', 'expected_revenue', 'partner_id', 'date_deadline', 'write_date', 'create_date']

    # Search for Phase 1 (Modified Original)
    # We accept exact match or close variations if needed, but strict is better for verification
    phase1 = models.execute_kw(db, uid, password, 'crm.lead', 'search_read', 
        [[['name', 'ilike', 'Azure Interior - Design Phase']]], 
        {'fields': fields, 'limit': 1})
    
    # Search for Phase 2 (New Created)
    phase2 = models.execute_kw(db, uid, password, 'crm.lead', 'search_read', 
        [[['name', 'ilike', 'Azure Interior - Implementation Phase']]], 
        {'fields': fields, 'limit': 1})

    # Search for original name (to check if it was renamed or just a new one created)
    original = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', '=', 'Azure Interior - Whole Office Design']]],
        {'fields': fields, 'limit': 1})

    result = {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "phase1_found": bool(phase1),
        "phase1_data": phase1[0] if phase1 else None,
        "phase2_found": bool(phase2),
        "phase2_data": phase2[0] if phase2 else None,
        "original_still_exists": bool(original),
        "original_data": original[0] if original else None,
        "screenshot_path": "/tmp/task_final.png"
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2, default=str)
        
    print("Export successful")

except Exception as e:
    print(f"Error exporting data: {e}", file=sys.stderr)
    # Create a basic failure result
    result = {
        "error": str(e),
        "task_start": $TASK_START,
        "task_end": $TASK_END
    }
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="