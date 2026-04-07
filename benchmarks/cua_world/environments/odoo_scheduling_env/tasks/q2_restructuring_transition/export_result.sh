#!/bin/bash
echo "=== Exporting q2_restructuring_transition result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/q2_restructuring_final.png

python3 << 'PYTHON_EOF'
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

result = {
    'rachel_contact': {'exists': False, 'email': '', 'job_position': '', 'phone': ''},
    'ops_daily_sync': {
        'exists': False,
        'attendee_names': [],
        'has_henry_kim': False,
        'has_rachel_torres': False,
        'location': '',
        'recurrency': False,
    },
    'qbr': {
        'exists': False,
        'start': '',
        'attendee_names': [],
        'has_henry_kim': False,
        'has_rachel_torres': False,
        'description': '',
    },
    'transition_checkin': {
        'exists': False,
        'recurrency': False,
        'rrule_type': '',
        'start': '',
        'stop': '',
        'mon': False,
        'thu': False,
        'attendee_names': [],
        'has_rachel_torres': False,
        'has_grace_patel': False,
        'description': '',
        'alarm_count': 0,
        'end_type': '',
        'count': 0,
    },
    'qbr_original_date': '',
    'next_monday': '',
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    def get_attendee_names(partner_ids):
        if not partner_ids:
            return []
        partners = models.execute_kw(db, uid, password, 'res.partner', 'read',
                                     [partner_ids, ['name']])
        return [p['name'] for p in partners]

    # -------------------------------------------------------------------
    # 1. Check Rachel Torres contact
    # -------------------------------------------------------------------
    rachel_ids = models.execute_kw(db, uid, password, 'res.partner', 'search',
                                   [[['name', 'ilike', 'Rachel Torres']]])
    if rachel_ids:
        rachel = models.execute_kw(db, uid, password, 'res.partner', 'read',
                                   [rachel_ids[:1], ['name', 'email', 'function', 'phone']])[0]
        result['rachel_contact'] = {
            'exists': True,
            'email': rachel.get('email', '') or '',
            'job_position': rachel.get('function', '') or '',
            'phone': rachel.get('phone', '') or '',
        }

    # -------------------------------------------------------------------
    # 2. Check Operations Daily Sync (recurring event)
    # -------------------------------------------------------------------
    sync_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                 [[['name', '=', 'Operations Daily Sync']]], {'limit': 1})
    if sync_ids:
        sync_event = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [sync_ids[:1], ['partner_ids', 'location', 'recurrency', 'recurrence_id']])[0]

        # If the event has a recurrence_id, read the master recurrence to get attendees
        partner_ids = sync_event.get('partner_ids', [])
        names = get_attendee_names(partner_ids)

        result['ops_daily_sync'] = {
            'exists': True,
            'attendee_names': names,
            'has_henry_kim': any('henry' in n.lower() and 'kim' in n.lower() for n in names),
            'has_rachel_torres': any('rachel' in n.lower() and 'torres' in n.lower() for n in names),
            'location': sync_event.get('location', '') or '',
            'recurrency': bool(sync_event.get('recurrency') or sync_event.get('recurrence_id')),
        }

    # -------------------------------------------------------------------
    # 3. Check Quarterly Business Review
    # -------------------------------------------------------------------
    qbr_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                [[['name', '=', 'Quarterly Business Review']]])
    if qbr_ids:
        qbr = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [qbr_ids[:1], ['start', 'partner_ids', 'description']])[0]

        names = get_attendee_names(qbr.get('partner_ids', []))

        result['qbr'] = {
            'exists': True,
            'start': qbr.get('start', ''),
            'attendee_names': names,
            'has_henry_kim': any('henry' in n.lower() and 'kim' in n.lower() for n in names),
            'has_rachel_torres': any('rachel' in n.lower() and 'torres' in n.lower() for n in names),
            'description': qbr.get('description', '') or '',
        }

    # -------------------------------------------------------------------
    # 4. Check Operations Transition Check-in
    # -------------------------------------------------------------------
    checkin_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
                                    [[['name', 'ilike', 'Operations Transition Check-in']]], {'limit': 1})
    if checkin_ids:
        checkin = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [checkin_ids[:1], [
                'start', 'stop', 'partner_ids', 'description', 'alarm_ids',
                'recurrency', 'rrule_type', 'rrule', 'recurrence_id',
                'mon', 'thu', 'end_type', 'count', 'interval',
            ]])[0]

        names = get_attendee_names(checkin.get('partner_ids', []))

        # Check recurrence details - may be on the event or on the recurrence record
        recurrency = bool(checkin.get('recurrency') or checkin.get('recurrence_id'))
        rrule_type = checkin.get('rrule_type', '') or ''
        mon_flag = checkin.get('mon', False)
        thu_flag = checkin.get('thu', False)
        end_type = checkin.get('end_type', '') or ''
        count = checkin.get('count', 0) or 0

        # If there's a recurrence_id, read the recurrence record for more detail
        rec_id = checkin.get('recurrence_id')
        if rec_id:
            rec_id_val = rec_id[0] if isinstance(rec_id, (list, tuple)) else rec_id
            try:
                rec = models.execute_kw(db, uid, password, 'calendar.recurrence', 'read',
                    [[rec_id_val], ['rrule_type', 'mon', 'thu', 'end_type', 'count', 'interval']])
                if rec:
                    rrule_type = rec[0].get('rrule_type', rrule_type) or rrule_type
                    mon_flag = rec[0].get('mon', mon_flag)
                    thu_flag = rec[0].get('thu', thu_flag)
                    end_type = rec[0].get('end_type', end_type) or end_type
                    count = rec[0].get('count', count) or count
            except Exception:
                pass

        result['transition_checkin'] = {
            'exists': True,
            'recurrency': recurrency,
            'rrule_type': rrule_type,
            'start': checkin.get('start', ''),
            'stop': checkin.get('stop', ''),
            'mon': bool(mon_flag),
            'thu': bool(thu_flag),
            'attendee_names': names,
            'has_rachel_torres': any('rachel' in n.lower() and 'torres' in n.lower() for n in names),
            'has_grace_patel': any('grace' in n.lower() and 'patel' in n.lower() for n in names),
            'description': checkin.get('description', '') or '',
            'alarm_count': len(checkin.get('alarm_ids', [])),
            'end_type': end_type,
            'count': count,
        }

    # -------------------------------------------------------------------
    # 5. Load ground truth dates
    # -------------------------------------------------------------------
    try:
        with open('/tmp/qbr_original_date.txt', 'r') as f:
            result['qbr_original_date'] = f.read().strip()
    except Exception:
        pass

    try:
        with open('/tmp/next_monday.txt', 'r') as f:
            result['next_monday'] = f.read().strip()
    except Exception:
        pass

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

    print("Export result:")
    print(json.dumps(result, indent=2))

except Exception as e:
    print(f"Export error: {e}", file=sys.stderr)
    result['error'] = str(e)
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
PYTHON_EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
