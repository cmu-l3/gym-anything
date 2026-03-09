#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_auditor_group results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Export Data from Django DB
# We query the Group and its Permissions to a JSON file.
# This runs INSIDE the container context.

EXPORT_SCRIPT="
import json
import sys
from django.contrib.auth.models import Group

result = {
    'group_found': False,
    'group_name': None,
    'permissions': [],
    'permission_count': 0,
    'has_forbidden': False,
    'error': None
}

try:
    # Check for the group
    group = Group.objects.filter(name='Regulatory Auditors').first()
    
    if group:
        result['group_found'] = True
        result['group_name'] = group.name
        
        # Get permissions
        perms = group.permissions.all()
        result['permission_count'] = perms.count()
        
        perm_list = []
        for p in perms:
            # Format: 'app_label.codename'
            perm_data = {
                'codename': p.codename,
                'name': p.name,
                'app_label': p.content_type.app_label,
                'model': p.content_type.model
            }
            perm_list.append(perm_data)
            
            # Check for forbidden actions (add/change/delete)
            if p.codename.startswith(('add_', 'change_', 'delete_')):
                result['has_forbidden'] = True
                
        result['permissions'] = perm_list
        
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result, indent=2))
"

# Execute the query and save to tmp
django_query "$EXPORT_SCRIPT" > /tmp/task_result_raw.json 2>/dev/null

# Filter the output to ensure only valid JSON is saved (django_query might output setup logs)
# We look for the JSON structure
cat /tmp/task_result_raw.json | grep -v "^Loading" | grep -v "^System" > /tmp/task_result.json || true

# 3. Metadata for export
# Add timestamp info to the result file
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# Use python to merge timestamp info into the JSON
python3 -c "
import json
import time

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['task_start_ts'] = $TASK_START
data['initial_count'] = int('$INITIAL_COUNT')
data['export_ts'] = time.time()

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Ensure permissions are open for the host to copy
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json