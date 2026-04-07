#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up process_part_time_transition task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Odoo is running and "Part Time 20 Hours" schedule exists
#    Also reset Audrey Peterson to "Standard 40 Hours" to ensure clean state
echo "Configuring Odoo data via XML-RPC..."
python3 << 'PYTHON_EOF'
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_hr'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- Step A: Ensure 'Part Time 20 Hours' calendar exists ---
    calendar_name = "Part Time 20 Hours"
    calendar_ids = models.execute_kw(db, uid, password, 'resource.calendar', 'search', [[['name', '=', calendar_name]]])
    
    if not calendar_ids:
        # Create a simple 20h calendar (Mon-Fri, 8-12)
        cal_id = models.execute_kw(db, uid, password, 'resource.calendar', 'create', [{
            'name': calendar_name,
            'hours_per_day': 4.0,
            'attendance_ids': [
                (0, 0, {'name': 'Monday Morning', 'dayofweek': '0', 'hour_from': 8, 'hour_to': 12, 'day_period': 'morning'}),
                (0, 0, {'name': 'Tuesday Morning', 'dayofweek': '1', 'hour_from': 8, 'hour_to': 12, 'day_period': 'morning'}),
                (0, 0, {'name': 'Wednesday Morning', 'dayofweek': '2', 'hour_from': 8, 'hour_to': 12, 'day_period': 'morning'}),
                (0, 0, {'name': 'Thursday Morning', 'dayofweek': '3', 'hour_from': 8, 'hour_to': 12, 'day_period': 'morning'}),
                (0, 0, {'name': 'Friday Morning', 'dayofweek': '4', 'hour_from': 8, 'hour_to': 12, 'day_period': 'morning'}),
            ]
        }])
        print(f"Created calendar '{calendar_name}' with ID {cal_id}")
    else:
        print(f"Calendar '{calendar_name}' already exists")

    # --- Step B: Reset Audrey Peterson to Standard 40 Hours ---
    emp_ids = models.execute_kw(db, uid, password, 'hr.employee', 'search', [[['name', '=', 'Audrey Peterson']]])
    if emp_ids:
        emp_id = emp_ids[0]
        # Find standard 40 hours calendar
        std_cals = models.execute_kw(db, uid, password, 'resource.calendar', 'search', [[['name', 'ilike', 'Standard 40']]])
        if std_cals:
            models.execute_kw(db, uid, password, 'hr.employee', 'write', [[emp_id], {'resource_calendar_id': std_cals[0]}])
            print(f"Reset Audrey Peterson (ID {emp_id}) to Standard 40 Hours")
        else:
            print("WARNING: 'Standard 40' calendar not found, skipping reset")
    else:
        print("ERROR: Audrey Peterson not found in demo data!", file=sys.stderr)
        sys.exit(1)

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# 3. Launch Firefox and navigate to Employees list
# This saves the agent one click and ensures they start in the right app
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="