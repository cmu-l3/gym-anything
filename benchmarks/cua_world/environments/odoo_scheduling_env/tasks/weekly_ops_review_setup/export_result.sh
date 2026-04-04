#!/bin/bash
echo "=== Exporting weekly_ops_review_setup result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/weekly_ops_review_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Search for 'Operations Weekly Review' event (case-insensitive)
    event_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                  [[['name', 'ilike', 'Operations Weekly Review']]])

    result = {
        'event_found': len(event_ids) > 0,
        'event_id': event_ids[0] if event_ids else None,
        'event_name': '',
        'has_recurrence': False,
        'rrule': '',
        'rrule_type': '',
        'attendee_count': 0,
        'northbridge_attendee_count': 0,
        'attendee_emails': [],
        'alarm_count': 0,
    }

    if event_ids:
        event = models.execute_kw(
            db, uid, 'admin', 'calendar.event', 'read',
            [event_ids[:1],
             ['name', 'recurrency', 'rrule', 'rrule_type', 'partner_ids', 'alarm_ids']]
        )[0]

        result['event_name'] = event.get('name', '')
        result['has_recurrence'] = bool(event.get('recurrency') or event.get('rrule'))
        result['rrule'] = event.get('rrule', '') or ''
        result['rrule_type'] = event.get('rrule_type', '') or ''
        result['alarm_count'] = len(event.get('alarm_ids', []))

        partner_ids = event.get('partner_ids', [])
        result['attendee_count'] = len(partner_ids)

        if partner_ids:
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'read',
                                         [partner_ids, ['name', 'email']])
            nb_partners = [p for p in partners
                           if (p.get('email') or '').endswith('@northbridge.org')]
            result['northbridge_attendee_count'] = len(nb_partners)
            result['attendee_emails'] = [p.get('email', '') for p in partners]

    with open('/tmp/weekly_ops_review_result.json', 'w') as f:
        json.dump(result, f)

    print("Export result:", json.dumps(result, indent=2))

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    with open('/tmp/weekly_ops_review_result.json', 'w') as f:
        json.dump({'event_found': False, 'error': str(e)}, f)
PYTHON_EOF

echo "=== Export complete ==="
