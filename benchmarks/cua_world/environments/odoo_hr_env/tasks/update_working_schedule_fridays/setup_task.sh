#!/bin/bash
set -e
echo "=== Setting up update_working_schedule_fridays task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------------------
# Reset "Standard 40 hours/week" to a known state (Mon-Fri 8-12, 13-17)
# This ensures the task is repeatable and starts from a clean state.
# ---------------------------------------------------------------------------
echo "Resetting working schedule via XML-RPC..."
python3 << 'PYEOF'
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

    # Find the calendar
    calendars = models.execute_kw(db, uid, password, 'resource.calendar', 'search', [[['name', '=', 'Standard 40 hours/week']]])
    
    if calendars:
        cal_id = calendars[0]
        # Remove all existing attendances (command 5: unlink all)
        models.execute_kw(db, uid, password, 'resource.calendar', 'write', [[cal_id], {'attendance_ids': [(5, 0, 0)]}])
        
        # Re-create standard Mon-Fri 8-12, 13-17
        attendances = []
        # Days: 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri
        for day in range(0, 5): 
            # Morning
            attendances.append((0, 0, {
                'name': 'Morning',
                'dayofweek': str(day),
                'hour_from': 8.0,
                'hour_to': 12.0,
                'day_period': 'morning'
            }))
            # Afternoon
            attendances.append((0, 0, {
                'name': 'Afternoon',
                'dayofweek': str(day),
                'hour_from': 13.0,
                'hour_to': 17.0,
                'day_period': 'afternoon'
            }))
            
        models.execute_kw(db, uid, password, 'resource.calendar', 'write', [[cal_id], {'attendance_ids': attendances}])
        print(f"Reset calendar {cal_id} to standard 40h week.")
    else:
        # Create it if it doesn't exist (fallback)
        print("Standard calendar not found, creating it...")
        attendances = []
        for day in range(0, 5):
            attendances.append((0, 0, {'name': 'Morning', 'dayofweek': str(day), 'hour_from': 8.0, 'hour_to': 12.0, 'day_period': 'morning'}))
            attendances.append((0, 0, {'name': 'Afternoon', 'dayofweek': str(day), 'hour_from': 13.0, 'hour_to': 17.0, 'day_period': 'afternoon'}))
            
        models.execute_kw(db, uid, password, 'resource.calendar', 'create', [{
            'name': 'Standard 40 hours/week',
            'attendance_ids': attendances
        }])

except Exception as e:
    print(f"Setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# ---------------------------------------------------------------------------
# Launch Firefox and navigate to Employees app
# ---------------------------------------------------------------------------
# We navigate to the Employees list. The agent must find "Configuration" > "Working Schedules"
ensure_firefox "http://localhost:8069/web#action=hr.open_view_employee_list_my"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="