#!/bin/bash
echo "=== Setting up hr_performance_calibration task ==="

source /workspace/scripts/task_utils.sh

python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Remove any existing 'Performance Review Calibration' events (clean slate)
    existing_calibration = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                             [[['name', 'ilike', 'Performance Review Calibration']]])
    if existing_calibration:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing_calibration])
        print(f"Removed {len(existing_calibration)} 'Performance Review Calibration' event(s)")

    # Ensure 'Annual Performance Review - Frank Rivera' exists as the target to delete
    annual_review = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                      [[['name', '=', 'Annual Performance Review - Frank Rivera']]])
    if not annual_review:
        # Recreate the individual annual review
        now = datetime.now()
        days_to_monday = (7 - now.weekday()) % 7 or 7
        next_monday = now + timedelta(days=days_to_monday)
        review_start = (next_monday + timedelta(days=4)).replace(
            hour=13, minute=0, second=0, microsecond=0)
        review_stop = review_start + timedelta(hours=1)

        frank_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                      [[['name', '=', 'Frank Rivera']]])

        event_data = {
            'name': 'Annual Performance Review - Frank Rivera',
            'start': review_start.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': review_stop.strftime('%Y-%m-%d %H:%M:%S'),
        }
        if frank_ids:
            event_data['partner_ids'] = [(4, frank_ids[0])]

        eid = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [event_data])
        print(f"Recreated 'Annual Performance Review - Frank Rivera' (id={eid})")
    else:
        print(f"'Annual Performance Review - Frank Rivera' exists (id={annual_review[0]})")

except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Record baseline AFTER cleanup so counts reflect clean starting state (Anti-pattern 3)
record_task_baseline "hr_performance_calibration"

# Navigate to the Odoo Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/hr_calibration_start.png

echo "Task start state: Odoo Calendar is open."
echo "Agent must: create recurring monthly 'Performance Review Calibration' with Frank Rivera, Grace Patel, Henry Kim, write description, AND delete 'Annual Performance Review - Frank Rivera'."
echo "=== hr_performance_calibration task setup complete ==="
