#!/bin/bash
echo "=== Exporting hr_performance_calibration result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/hr_calibration_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Check for 'Performance Review Calibration' event
    calibration_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                        [[['name', 'ilike', 'Performance Review Calibration']]])

    # Check if 'Annual Performance Review - Frank Rivera' was deleted
    annual_ids = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                   [[['name', '=', 'Annual Performance Review - Frank Rivera']]])

    result = {
        'calibration_found': len(calibration_ids) > 0,
        'calibration_id': calibration_ids[0] if calibration_ids else None,
        'has_recurrence': False,
        'rrule': '',
        'rrule_type': '',
        'attendee_count': 0,
        'attendee_names': [],
        'has_frank_rivera': False,
        'has_grace_patel': False,
        'has_henry_kim': False,
        'description': '',
        'annual_review_deleted': len(annual_ids) == 0,
    }

    if calibration_ids:
        event = models.execute_kw(
            db, uid, 'admin', 'calendar.event', 'read',
            [calibration_ids[:1],
             ['name', 'recurrency', 'rrule', 'rrule_type', 'partner_ids', 'description']]
        )[0]

        result['has_recurrence'] = bool(event.get('recurrency') or event.get('rrule'))
        result['rrule'] = event.get('rrule', '') or ''
        result['rrule_type'] = event.get('rrule_type', '') or ''
        result['description'] = event.get('description', '') or ''

        partner_ids = event.get('partner_ids', [])
        result['attendee_count'] = len(partner_ids)

        if partner_ids:
            partners = models.execute_kw(db, uid, 'admin', 'res.partner', 'read',
                                         [partner_ids, ['name']])
            names = [p['name'] for p in partners]
            result['attendee_names'] = names
            result['has_frank_rivera'] = any('frank' in n.lower() and 'rivera' in n.lower() for n in names)
            result['has_grace_patel'] = any('grace' in n.lower() and 'patel' in n.lower() for n in names)
            result['has_henry_kim'] = any('henry' in n.lower() and 'kim' in n.lower() for n in names)

    with open('/tmp/hr_calibration_result.json', 'w') as f:
        json.dump(result, f)

    print("Export result:", json.dumps(result, indent=2))

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    with open('/tmp/hr_calibration_result.json', 'w') as f:
        json.dump({'calibration_found': False, 'annual_review_deleted': False, 'error': str(e)}, f)
PYTHON_EOF

echo "=== Export complete ==="
