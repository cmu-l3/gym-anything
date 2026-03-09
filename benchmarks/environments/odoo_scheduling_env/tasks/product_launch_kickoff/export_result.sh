#!/bin/bash
echo "=== Exporting product_launch_kickoff result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/product_launch_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check if 'Product Launch Kickoff' was created
    kickoff_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                    [[['name', 'ilike', 'Product Launch Kickoff']]])

    # Check if 'Sprint Planning - Engineering' was deleted
    sprint_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                   [[['name', '=', 'Sprint Planning - Engineering']]])

    result = {
        'kickoff_found': len(kickoff_ids) > 0,
        'kickoff_attendee_count': 0,
        'kickoff_attendee_names': [],
        'kickoff_location': '',
        'kickoff_description': '',
        'sprint_deleted': len(sprint_ids) == 0,
    }

    if kickoff_ids:
        event = models.execute_kw(
            db, uid, 'admin', 'calendar.event', 'read',
            [kickoff_ids[:1],
             ['name', 'location', 'description', 'partner_ids']]
        )[0]

        result['kickoff_location'] = event.get('location', '') or ''
        result['kickoff_description'] = event.get('description', '') or ''

        partner_ids = event.get('partner_ids', [])
        result['kickoff_attendee_count'] = len(partner_ids)
        if partner_ids:
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'read',
                                         [partner_ids, ['name']])
            result['kickoff_attendee_names'] = [p['name'] for p in partners]

    with open('/tmp/product_launch_result.json', 'w') as f:
        json.dump(result, f)

    print("Export result:", json.dumps(result, indent=2))

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    with open('/tmp/product_launch_result.json', 'w') as f:
        json.dump({'kickoff_found': False, 'sprint_deleted': False, 'error': str(e)}, f)
PYTHON_EOF

echo "=== Export complete ==="
