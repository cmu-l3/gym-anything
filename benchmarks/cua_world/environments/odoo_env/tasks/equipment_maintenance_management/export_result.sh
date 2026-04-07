#!/bin/bash
# Export script for equipment_maintenance_management task
# Queries Odoo for the new equipment and maintenance request

echo "=== Exporting equipment_maintenance_management Result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ ! -f /tmp/equipment_maintenance_setup.json ]; then
    echo '{"error": "setup_data_missing"}' > /tmp/task_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/equipment_maintenance_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# Get task start time
try:
    with open('/tmp/task_start_time.txt') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

# ─── 1. Check for New Equipment (CNC Machine) ────────────────────────────────
NEW_EQUIP_NAME = "CNC Vertical Milling Machine - Haas VF-2SS"
NEW_CAT_NAME = "CNC Machinery"

# Fuzzy search for equipment
equips = execute('maintenance.equipment', 'search_read',
    [[['name', 'ilike', 'CNC'], ['name', 'ilike', 'Milling']]],
    {'fields': ['id', 'name', 'category_id', 'period', 'maintenance_team_id', 'department_id', 'create_date']})

found_equip = None
# Filter specifically for one created AFTER task start (anti-gaming)
for eq in equips:
    # Odoo dates are strings 'YYYY-MM-DD HH:MM:SS'
    cdate = datetime.strptime(eq['create_date'], '%Y-%m-%d %H:%M:%S')
    if cdate.timestamp() > task_start:
        found_equip = eq
        break

# Check Category details if equipment found
category_correct = False
if found_equip and found_equip['category_id']:
    cat_id = found_equip['category_id'][0]
    cat_name = found_equip['category_id'][1]
    if NEW_CAT_NAME.lower() in cat_name.lower():
        category_correct = True
    # Double check actual category record if needed (not strictly necessary if name matches)

# ─── 2. Check for Corrective Maintenance Request ─────────────────────────────
TARGET_EQUIP_ID = setup['target_equip_id']
REQUEST_SUBJECT = "Hydraulic pressure loss"

# Search for requests linked to the specific Hydraulic Press ID created in setup
requests = execute('maintenance.request', 'search_read',
    [[['equipment_id', '=', TARGET_EQUIP_ID]]],
    {'fields': ['id', 'name', 'priority', 'description', 'create_date', 'equipment_id']})

found_request = None
for req in requests:
    cdate = datetime.strptime(req['create_date'], '%Y-%m-%d %H:%M:%S')
    # Must be created during task
    if cdate.timestamp() > task_start:
        found_request = req
        break

# Check description/chatter if description field is empty (sometimes agents put it in chatter)
request_description = ""
if found_request:
    request_description = found_request.get('description') or ""
    # If description empty, check mail.message
    if not request_description:
        messages = execute('mail.message', 'search_read',
            [[['model', '=', 'maintenance.request'], ['res_id', '=', found_request['id']], ['message_type', '=', 'comment']]],
            {'fields': ['body'], 'limit': 1})
        if messages:
            request_description = messages[0]['body']

# ─── Build Result ────────────────────────────────────────────────────────────
result = {
    'task_start': task_start,
    'setup_target_id': TARGET_EQUIP_ID,
    
    # Equipment Checks
    'equip_found': bool(found_equip),
    'equip_name': found_equip['name'] if found_equip else None,
    'equip_period': found_equip['period'] if found_equip else 0,
    'equip_category_name': found_equip['category_id'][1] if found_equip and found_equip['category_id'] else None,
    'category_correct': category_correct,
    'equip_has_team': bool(found_equip and found_equip['maintenance_team_id']),
    
    # Request Checks
    'request_found': bool(found_request),
    'request_name': found_request['name'] if found_request else None,
    'request_priority': found_request['priority'] if found_request else '0', # '0','1','2','3'
    'request_linked_id': found_request['equipment_id'][0] if found_request and found_request['equipment_id'] else None,
    'request_description': request_description,
    
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF