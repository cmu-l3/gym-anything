#!/bin/bash
echo "=== Setting up board_meeting_restructure task ==="

source /workspace/scripts/task_utils.sh

# Prepare the Quarterly Business Review event:
# - Remove Karen Lee from QBR attendees (agent must re-add Legal Counsel)
# - Remove all alarms (agent must add reminder)
# - Record original QBR start date for verifier comparison
# Ensure Budget Committee Meeting exists as the target to delete
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys, json
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find QBR
    qbr_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                [[['name', '=', 'Quarterly Business Review']]])
    if not qbr_ids:
        print("ERROR: 'Quarterly Business Review' not found!", file=sys.stderr)
        sys.exit(1)

    qbr_id = qbr_ids[0]
    qbr_event = models.execute_kw(db, uid, 'admin', 'calendar.event', 'read',
                                  [[qbr_id], ['start', 'stop', 'partner_ids']])[0]

    # Record original QBR start for the verifier
    original_start = qbr_event['start']
    with open('/tmp/qbr_original_start.txt', 'w') as f:
        f.write(original_start)
    print(f"Recorded original QBR start: {original_start}")

    # Find Karen Lee's partner ID
    karen_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                  [[['name', '=', 'Karen Lee']]])
    karen_id = karen_ids[0] if karen_ids else None

    # Reset QBR: remove Karen Lee, remove alarms
    write_vals = {'alarm_ids': [(5, 0, 0)]}  # clear all alarms
    if karen_id:
        write_vals['partner_ids'] = [(3, karen_id)]

    models.execute_kw(db, uid, 'admin', 'calendar.event', 'write',
                      [[qbr_id], write_vals])
    print(f"Reset QBR: removed Karen Lee and all alarms (qbr_id={qbr_id})")

    # Ensure Budget Committee Meeting exists as deletion target
    budget_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                   [[['name', '=', 'Budget Committee Meeting']]])
    if not budget_ids:
        # Recreate it in week 2 of the data anchor
        now = datetime.now()
        days_to_monday = (7 - now.weekday()) % 7 or 7
        next_monday = now + timedelta(days=days_to_monday)
        budget_start = (next_monday + timedelta(days=10)).replace(
            hour=15, minute=0, second=0, microsecond=0)
        budget_stop = budget_start + timedelta(hours=1, minutes=30)

        grace_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                      [[['name', '=', 'Grace Patel']]])
        henry_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                      [[['name', '=', 'Henry Kim']]])
        bob_ids = models.execute_kw(db, uid, 'admin', 'res.partner', 'search',
                                    [[['name', '=', 'Bob Williams']]])

        partner_ids = [(4, pid) for pid in [
            grace_ids[0] if grace_ids else None,
            henry_ids[0] if henry_ids else None,
            bob_ids[0] if bob_ids else None,
        ] if pid]

        event_data = {
            'name': 'Budget Committee Meeting',
            'start': budget_start.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': budget_stop.strftime('%Y-%m-%d %H:%M:%S'),
            'location': 'Board Room',
            'description': 'Monthly budget review and department budget approvals.',
        }
        if partner_ids:
            event_data['partner_ids'] = partner_ids

        eid = models.execute_kw(db, uid, 'admin', 'calendar.event', 'create', [event_data])
        print(f"Recreated 'Budget Committee Meeting' (id={eid})")
    else:
        print(f"'Budget Committee Meeting' exists (id={budget_ids[0]})")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Record baseline AFTER setup so counts reflect clean starting state (Anti-pattern 3)
record_task_baseline "board_meeting_restructure"

# Navigate to the Quarterly Business Review form so agent sees the target event
QBR_ID=$(python3 -c "
import xmlrpc.client
url = 'http://localhost:8069'
db = 'odoo_scheduling'
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, 'admin', 'admin', {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search', [[['name', '=', 'Quarterly Business Review']]])
print(ids[0] if ids else '')
" 2>/dev/null)

ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
if [ -n "$QBR_ID" ]; then
    navigate_firefox "http://localhost:8069/web#id=$QBR_ID&model=calendar.event&view_type=form"
    sleep 3
else
    navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
    sleep 3
fi

take_screenshot /tmp/board_restructure_start.png

echo "Task start state: Quarterly Business Review form is open."
echo "Agent must: postpone QBR by 1 week, add Karen Lee, add reminder, AND delete Budget Committee Meeting."
echo "=== board_meeting_restructure task setup complete ==="
