#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting archive_stale_opportunities results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ACTIVE_COUNT=$(cat /tmp/initial_active_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Use Python to gather precise verification data from Odoo
python3 - << PYEOF
import xmlrpc.client
import json
import sys
import time
from datetime import datetime

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"
task_start_ts = ${TASK_START}
initial_count = ${INITIAL_ACTIVE_COUNT}

result = {
    "targets": {},
    "initial_active_count": initial_count,
    "final_active_count": 0,
    "collateral_damage": False,
    "timestamp_check_passed": False,
    "task_start_ts": task_start_ts,
    "timestamp": datetime.now().isoformat()
}

target_names = [
    "Cloud Migration Assessment - GlobalTech Solutions",
    "POS System Rollout - Bay Area Retailers",
    "Data Analytics Platform - Meridian Corp"
]

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check targets
    # We use active_test=False to find them even if they are archived (which is the goal)
    target_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search_read',
        [[['name', 'in', target_names]]],
        {'fields': ['name', 'active', 'write_date'], 'context': {'active_test': False}})

    modified_count = 0

    for target in target_ids:
        name = target['name']
        is_active = target['active']
        write_date_str = target['write_date'] # format: '2023-10-27 10:00:00'
        
        # Odoo stores UTC. We need to compare roughly with task start.
        # Simple check: timestamp string vs task start timestamp
        # Converting Odoo string to timestamp
        write_dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
        write_ts = write_dt.timestamp()
        
        was_modified_recently = write_ts >= task_start_ts
        
        if was_modified_recently and not is_active:
            modified_count += 1

        result["targets"][name] = {
            "active": is_active,
            "modified_after_start": was_modified_recently,
            "write_date": write_date_str
        }

    # Timestamp check passes if at least one target was modified after start
    result["timestamp_check_passed"] = (modified_count > 0)

    # Check for collateral damage
    # Count current active opportunities
    current_active_count = models.execute_kw(db, uid, password, 'crm.lead', 'search_count',
        [[['type', '=', 'opportunity'], ['active', '=', True]]])
    
    result["final_active_count"] = current_active_count
    
    # Logic: 
    # If 3 targets were successfully archived, final count should be initial - 3.
    # If only 2 were archived, final count should be initial - 2.
    # Collateral damage happens if final count is LOWER than (initial - archived_targets).
    
    archived_targets_count = sum(1 for t in result["targets"].values() if not t["active"])
    expected_count = initial_count - archived_targets_count
    
    if current_active_count < expected_count:
        result["collateral_damage"] = True
        result["collateral_details"] = f"Expected {expected_count} active, found {current_active_count}"
    elif current_active_count > expected_count:
        # This implies new opportunities were created or archived ones restored?
        # Less critical than destroying data, but still messy.
        result["collateral_damage"] = False # We'll be lenient on creations, strict on archiving
        result["collateral_details"] = "Count higher than expected (new records created?)"
    else:
        result["collateral_damage"] = False

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json