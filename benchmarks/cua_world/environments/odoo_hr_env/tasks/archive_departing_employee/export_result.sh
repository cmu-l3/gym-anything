#!/bin/bash
echo "=== Exporting archive_departing_employee result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ACTIVE_COUNT=$(cat /tmp/initial_active_count.txt 2>/dev/null || echo "0")

# Take final screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Verify Data State via XML-RPC
# ---------------------------------------------------------------------------
python3 << PYTHON_EOF
import xmlrpc.client
import sys
import json
import time

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_active_count": int("$INITIAL_ACTIVE_COUNT"),
    "walter_found": False,
    "walter_active": True,  # Default assumption
    "walter_exists_in_db": False,
    "final_active_count": 0,
    "screenshot_path": "/tmp/task_final.png"
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Check current active count
    result['final_active_count'] = models.execute_kw(db, uid, password, 'hr.employee', 'search_count', 
                                                   [[['active', '=', True]]])

    # 2. Check specific employee status
    # Search including inactive records to verify archival vs deletion
    # Odoo search domain for active=False requires specific context or '|' operator
    ids = models.execute_kw(db, uid, password, 'hr.employee', 'search',
                            [[['name', '=', 'Walter Horton'], '|', ['active', '=', True], ['active', '=', False]]])
    
    if ids:
        result['walter_exists_in_db'] = True
        # Read the 'active' field
        data = models.execute_kw(db, uid, password, 'hr.employee', 'read', [ids, ['active']])
        if data:
            result['walter_found'] = True
            result['walter_active'] = data[0]['active']
    
except Exception as e:
    result['error'] = str(e)

# Write result to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported result JSON:")
print(json.dumps(result, indent=2))
PYTHON_EOF

# Ensure permissions (sometimes python creates root-owned files in docker)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="