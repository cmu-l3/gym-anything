#!/bin/bash
echo "=== Exporting board_meeting_restructure result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/board_restructure_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Read original QBR start from setup file
    original_start = ''
    try:
        with open('/tmp/qbr_original_start.txt', 'r') as f:
            original_start = f.read().strip()
    except Exception:
        pass

    # Find current QBR
    qbr_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                [[['name', '=', 'Quarterly Business Review']]])

    # Check if Budget Committee Meeting was deleted
    budget_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                   [[['name', '=', 'Budget Committee Meeting']]])

    result = {
        'qbr_found': len(qbr_ids) > 0,
        'qbr_start': '',
        'qbr_original_start': original_start,
        'karen_lee_attendee': False,
        'alarm_count': 0,
        'attendee_names': [],
        'budget_meeting_deleted': len(budget_ids) == 0,
    }

    if qbr_ids:
        event = models.execute_kw(
            db, uid, 'admin', 'calendar.event', 'read',
            [qbr_ids[:1],
             ['name', 'start', 'partner_ids', 'alarm_ids']]
        )[0]

        result['qbr_start'] = str(event.get('start', ''))
        result['alarm_count'] = len(event.get('alarm_ids', []))

        partner_ids = event.get('partner_ids', [])
        if partner_ids:
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'read',
                                         [partner_ids, ['name']])
            names = [p['name'] for p in partners]
            result['attendee_names'] = names
            result['karen_lee_attendee'] = any(
                'karen' in n.lower() and 'lee' in n.lower()
                for n in names
            )

    with open('/tmp/board_restructure_result.json', 'w') as f:
        json.dump(result, f)

    print("Export result:", json.dumps(result, indent=2))

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    with open('/tmp/board_restructure_result.json', 'w') as f:
        json.dump({'qbr_found': False, 'budget_meeting_deleted': False, 'error': str(e)}, f)
PYTHON_EOF

echo "=== Export complete ==="
