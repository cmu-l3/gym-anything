#!/bin/bash
echo "=== Setting up q2_restructuring_transition task ==="

source /workspace/scripts/task_utils.sh

# Calculate key dates using Python
eval $(python3 -c "
from datetime import datetime, timedelta
now = datetime.now()
# Next Monday
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)
# Next weekday from tomorrow (for recurring event start)
tomorrow = now + timedelta(days=1)
if tomorrow.weekday() >= 5:
    days_until_weekday = (7 - tomorrow.weekday()) % 7
    sync_start = tomorrow + timedelta(days=days_until_weekday)
else:
    sync_start = tomorrow
print(f'NEXT_MONDAY=\"{next_monday.strftime(\"%Y-%m-%d\")}\"')
print(f'SYNC_START=\"{sync_start.strftime(\"%Y-%m-%d\")}\"')
")

echo "Next Monday: $NEXT_MONDAY"
echo "Sync Start: $SYNC_START"

# Save dates for export/verifier
echo "$NEXT_MONDAY" > /tmp/next_monday.txt

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys
from datetime import datetime, timedelta

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # ---------------------------------------------------------------
    # Phase 1: Clean up from any prior run
    # ---------------------------------------------------------------

    # Delete any Rachel Torres contact
    rachel_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                   [[['name', 'ilike', 'Rachel Torres']]])
    if rachel_ids:
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [rachel_ids])
        print(f"Cleaned up {len(rachel_ids)} 'Rachel Torres' contact(s)")

    # Delete any existing 'Operations Transition Check-in' events
    checkin_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                    [[['name', 'ilike', 'Operations Transition Check-in']]])
    if checkin_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [checkin_ids])
        print(f"Cleaned up {len(checkin_ids)} 'Operations Transition Check-in' event(s)")

    # ---------------------------------------------------------------
    # Phase 2: Convert "Operations Daily Sync" to a recurring event
    # ---------------------------------------------------------------

    # Get partner IDs needed for the recurring event
    def get_pid(name):
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                [[['name', '=', name]]])
        return ids[0] if ids else None

    p_grace = get_pid("Grace Patel")
    p_henry = get_pid("Henry Kim")
    p_bob = get_pid("Bob Williams")

    # Delete existing single "Operations Daily Sync" event(s)
    sync_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                 [[['name', '=', 'Operations Daily Sync']]])
    if sync_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [sync_ids])
        print(f"Deleted {len(sync_ids)} existing 'Operations Daily Sync' event(s)")

    # Compute start date: next weekday from tomorrow
    now = datetime.now()
    tomorrow = now + timedelta(days=1)
    if tomorrow.weekday() >= 5:
        days_until_weekday = (7 - tomorrow.weekday()) % 7
        sync_start = tomorrow + timedelta(days=days_until_weekday)
    else:
        sync_start = tomorrow
    sync_start_str = sync_start.strftime('%Y-%m-%d')

    # Create as a recurring weekday event (weekly on Mon-Fri)
    partner_links = []
    for pid in [p_grace, p_henry, p_bob]:
        if pid:
            partner_links.append((4, pid))

    event_vals = {
        'name': 'Operations Daily Sync',
        'start': f'{sync_start_str} 14:00:00',
        'stop': f'{sync_start_str} 14:30:00',
        'duration': 0.5,
        'recurrency': True,
        'rrule_type': 'weekly',
        'interval': 1,
        'mon': True, 'tue': True, 'wed': True, 'thu': True, 'fri': True,
        'sat': False, 'sun': False,
        'end_type': 'forever',
        'location': 'Operations Hub',
        'partner_ids': partner_links,
    }
    sync_id = models.execute_kw(db, uid, password, 'calendar.event', 'create', [event_vals])
    print(f"Created recurring 'Operations Daily Sync' (id={sync_id}) starting {sync_start_str}")

    # ---------------------------------------------------------------
    # Phase 3: Reset "Quarterly Business Review" to baseline
    # ---------------------------------------------------------------

    qbr_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                [[['name', '=', 'Quarterly Business Review']]])
    if qbr_ids:
        qbr = models.execute_kw(db, uid, password, 'calendar.event', 'read',
                                [qbr_ids[:1], ['start', 'stop', 'partner_ids', 'description']])[0]

        # Save original date for the verifier
        original_start = qbr['start']
        with open('/tmp/qbr_original_date.txt', 'w') as f:
            f.write(original_start)
        print(f"QBR original start date saved: {original_start}")

        # Ensure Henry Kim is in attendees (restore if removed from prior run)
        current_partners = qbr.get('partner_ids', [])
        if p_henry and p_henry not in current_partners:
            models.execute_kw(db, uid, password, 'calendar.event', 'write',
                              [qbr_ids[:1], {'partner_ids': [(4, p_henry)]}])
            print("Restored Henry Kim to QBR attendees")

        # Remove Rachel Torres from attendees if present from a prior run
        rachel_in_qbr = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                          [[['name', 'ilike', 'Rachel Torres']]])
        for rid in rachel_in_qbr:
            if rid in current_partners:
                models.execute_kw(db, uid, password, 'calendar.event', 'write',
                                  [qbr_ids[:1], {'partner_ids': [(3, rid)]}])
                print("Removed stale Rachel Torres from QBR attendees")

        # Reset description to original
        models.execute_kw(db, uid, password, 'calendar.event', 'write',
                          [qbr_ids[:1], {
                              'description': 'Full Q2 business review: financials, product, sales, and HR.'
                          }])
        print("Reset QBR description to original")
    else:
        print("WARNING: 'Quarterly Business Review' event not found!", file=sys.stderr)
        with open('/tmp/qbr_original_date.txt', 'w') as f:
            f.write('')

    print("Setup complete.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

# Record baseline AFTER cleanup so counts reflect clean starting state
record_task_baseline "q2_restructuring_transition"

# Ensure Firefox is running and logged in, navigated to Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/q2_restructuring_start.png

echo "Task start state: Odoo Calendar is open."
echo "Agent must: create Rachel Torres contact, modify recurring Ops Daily Sync, reschedule QBR, create recurring Transition Check-in."
echo "=== q2_restructuring_transition task setup complete ==="
