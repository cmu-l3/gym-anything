#!/bin/bash
echo "=== Exporting quarterly_pipeline_audit Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || \
        DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/quarterly_pipeline_audit_end.png

# Query all relevant state via Python/XML-RPC
python3 << 'PYEOF'
import json
import xmlrpc.client
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoodb'
USER = 'admin'
PASS = 'admin'

common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
uid = common.authenticate(DB, USER, PASS, {})
models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

# Load seed IDs
try:
    with open('/tmp/pipeline_audit_ids.json') as f:
        seed_data = json.load(f)
except Exception as e:
    print(f"FATAL: Cannot load seed IDs: {e}")
    import sys; sys.exit(1)

task_start_ts = int(open('/tmp/task_start_timestamp').read().strip())
start_dt = datetime.fromtimestamp(task_start_ts).strftime('%Y-%m-%d %H:%M:%S')

result = {
    'task_start_dt': start_dt,
    'task_start_ts': task_start_ts,
    'infrastructure': {},
    'opportunities': {},
    'errors': [],
}

# ========== CHECK INFRASTRUCTURE ==========

# 1. Check "Negotiation" stage exists and position
all_stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search_read',
    [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
stage_names_ordered = [s['name'] for s in all_stages]
stage_map = {s['name']: {'id': s['id'], 'sequence': s['sequence']} for s in all_stages}

neg_info = stage_map.get('Negotiation')
prop_info = stage_map.get('Proposition') or stage_map.get('Proposition (Draft)')
won_info = stage_map.get('Won')

negotiation_exists = neg_info is not None
negotiation_position_ok = False
if neg_info and prop_info and won_info:
    negotiation_position_ok = (prop_info['sequence'] < neg_info['sequence'] < won_info['sequence'])

result['infrastructure']['negotiation_stage'] = {
    'exists': negotiation_exists,
    'position_ok': negotiation_position_ok,
    'stage_id': neg_info['id'] if neg_info else None,
    'sequence': neg_info['sequence'] if neg_info else None,
    'all_stages_ordered': stage_names_ordered,
}

# 2. Check "Champion Left Organization" lost reason
clr = models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'search_read',
    [[['name', '=', 'Champion Left Organization']]], {'fields': ['id', 'name']})
result['infrastructure']['lost_reason'] = {
    'exists': len(clr) > 0,
    'id': clr[0]['id'] if clr else None,
}

# 3. Check "Q2 Priority Accounts" sales team
q2_team = models.execute_kw(DB, uid, PASS, 'crm.team', 'search_read',
    [[['name', '=', 'Q2 Priority Accounts']]], {'fields': ['id', 'name', 'user_id']})
result['infrastructure']['sales_team'] = {
    'exists': len(q2_team) > 0,
    'id': q2_team[0]['id'] if q2_team else None,
    'leader': q2_team[0]['user_id'][1] if q2_team and q2_team[0].get('user_id') else None,
}
q2_team_id = q2_team[0]['id'] if q2_team else None

# ========== CHECK EACH OPPORTUNITY ==========

opp_ids = seed_data.get('opportunities', {})

# Helper: get tag names for a crm.lead
def get_opp_tags(lead_data):
    tag_ids = lead_data.get('tag_ids', [])
    if not tag_ids:
        return []
    tags = models.execute_kw(DB, uid, PASS, 'crm.tag', 'read',
        [tag_ids], {'fields': ['name']})
    return [t['name'] for t in tags]

# Query all 7 opportunities (including active=False for lost ones)
for key, oid in opp_ids.items():
    try:
        opp_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'read',
            [[oid]], {
                'fields': ['name', 'stage_id', 'probability', 'expected_revenue',
                           'priority', 'active', 'lost_reason_id', 'partner_id',
                           'team_id', 'tag_ids', 'write_date'],
                'context': {'active_test': False}  # include archived/lost
            })
        if not opp_data:
            # Try without active_test
            opp_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search_read',
                [[['id', '=', oid], '|', ['active', '=', True], ['active', '=', False]]],
                {'fields': ['name', 'stage_id', 'probability', 'expected_revenue',
                            'priority', 'active', 'lost_reason_id', 'partner_id',
                            'team_id', 'tag_ids', 'write_date']})
        if opp_data:
            d = opp_data[0]
            tag_names = get_opp_tags(d)
            result['opportunities'][key] = {
                'id': oid,
                'name': d.get('name', ''),
                'stage_name': d['stage_id'][1] if d.get('stage_id') else None,
                'stage_id': d['stage_id'][0] if d.get('stage_id') else None,
                'probability': d.get('probability', 0),
                'expected_revenue': d.get('expected_revenue', 0),
                'priority': d.get('priority', '0'),
                'active': d.get('active', True),
                'lost_reason_name': d['lost_reason_id'][1] if d.get('lost_reason_id') else None,
                'partner_id': d['partner_id'][0] if d.get('partner_id') else None,
                'partner_name': d['partner_id'][1] if d.get('partner_id') else None,
                'team_id': d['team_id'][0] if d.get('team_id') else None,
                'team_name': d['team_id'][1] if d.get('team_id') else None,
                'tag_names': tag_names,
                'has_q1_reviewed': 'Q1-Reviewed' in tag_names,
                'is_on_q2_team': (d['team_id'][0] == q2_team_id) if d.get('team_id') and q2_team_id else False,
                'write_date': d.get('write_date', ''),
            }
        else:
            result['opportunities'][key] = {'id': oid, 'error': 'not_found'}
    except Exception as e:
        result['opportunities'][key] = {'id': oid, 'error': str(e)}
        result['errors'].append(f"Error checking {key}: {e}")

# ========== CHECK OPP4 NAME CHANGE (might have been renamed) ==========
# Search by ID since name may have changed
# Already captured above via seed ID

# ========== CHECK OPP6 ACTIVITY ==========
opp6_id = opp_ids.get('opp6')
if opp6_id:
    try:
        activities = models.execute_kw(DB, uid, PASS, 'mail.activity', 'search_read',
            [[['res_model', '=', 'crm.lead'], ['res_id', '=', opp6_id]]],
            {'fields': ['activity_type_id', 'date_deadline', 'summary', 'note']})
        opp6_activities = []
        for act in activities:
            opp6_activities.append({
                'type_name': act['activity_type_id'][1] if act.get('activity_type_id') else None,
                'date_deadline': act.get('date_deadline', ''),
                'summary': act.get('summary', ''),
            })
        result['opp6_activities'] = opp6_activities
    except Exception as e:
        result['opp6_activities'] = []
        result['errors'].append(f"Error checking opp6 activities: {e}")

# ========== CHECK OPP7 CONTACT (Elena Foster) ==========
opp7_id = opp_ids.get('opp7')
try:
    elena = models.execute_kw(DB, uid, PASS, 'res.partner', 'search_read',
        [[['name', 'ilike', 'Elena Foster'], ['is_company', '=', False]]],
        {'fields': ['id', 'name', 'parent_id', 'email', 'phone', 'mobile', 'function'],
         'limit': 5})
    if elena:
        e = elena[0]
        redwood_partner_id = seed_data['partners'].get('redwood')
        result['elena_foster'] = {
            'exists': True,
            'id': e['id'],
            'name': e['name'],
            'parent_id': e['parent_id'][0] if e.get('parent_id') else None,
            'parent_name': e['parent_id'][1] if e.get('parent_id') else None,
            'linked_to_redwood': (e['parent_id'][0] == redwood_partner_id) if e.get('parent_id') and redwood_partner_id else False,
            'email': e.get('email', ''),
            'phone': e.get('phone', ''),
            'mobile': e.get('mobile', ''),
            'job_title': e.get('function', ''),
        }
    else:
        result['elena_foster'] = {'exists': False}
except Exception as e:
    result['elena_foster'] = {'exists': False, 'error': str(e)}
    result['errors'].append(f"Error checking Elena Foster: {e}")

# ========== WRITE RESULT ==========

with open('/tmp/task_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

print(json.dumps(result, indent=2, default=str))

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/task_result_temp.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="
