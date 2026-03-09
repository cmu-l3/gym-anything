#!/bin/bash
echo "=== Exporting investor_meeting_update result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/investor_meeting_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Find the Investor Update Preparation event
    event_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                  [[['name', '=', 'Investor Update Preparation']]])

    result = {
        'event_found': len(event_ids) > 0,
        'karen_lee_attendee': False,
        'location': '',
        'description': '',
        'alarm_count': 0,
        'attendee_names': [],
    }

    if event_ids:
        event = models.execute_kw(
            db, uid, 'admin', 'calendar.event', 'read',
            [event_ids[:1],
             ['name', 'location', 'description', 'partner_ids', 'alarm_ids']]
        )[0]

        result['location'] = event.get('location', '') or ''
        result['description'] = event.get('description', '') or ''
        result['alarm_count'] = len(event.get('alarm_ids', []))

        partner_ids = event.get('partner_ids', [])
        if partner_ids:
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'read',
                                         [partner_ids, ['name', 'email']])
            result['attendee_names'] = [p['name'] for p in partners]
            result['karen_lee_attendee'] = any(
                'karen' in p['name'].lower() and 'lee' in p['name'].lower()
                for p in partners
            )

    with open('/tmp/investor_meeting_result.json', 'w') as f:
        json.dump(result, f)

    print("Export result:", json.dumps(result, indent=2))

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    with open('/tmp/investor_meeting_result.json', 'w') as f:
        json.dump({'event_found': False, 'error': str(e)}, f)
PYTHON_EOF

echo "=== Export complete ==="
