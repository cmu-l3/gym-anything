#!/bin/bash
echo "=== Exporting end_of_quarter_pipeline_restructure Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || \
        DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/eoq_restructure_end.png

# Query all relevant state via Python/XML-RPC
python3 << 'PYEOF'
import json
import re
import xmlrpc.client
from datetime import datetime

URL = 'http://localhost:8069'
DB = 'odoodb'
USER = 'admin'
PASS = 'admin'

common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
uid = common.authenticate(DB, USER, PASS, {})
models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

def ex(model, method, args, kwargs=None):
    return models.execute_kw(DB, uid, PASS, model, method, args, kwargs or {})

# Load seed IDs
try:
    with open('/tmp/eoq_restructure_ids.json') as f:
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
    'duplicate_merge': {},
    'errors': [],
}

# ========== CHECK INFRASTRUCTURE ==========

# 1. Check "Negotiation" stage exists and position
all_stages = ex('crm.stage', 'search_read',
    [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
stage_names_ordered = [s['name'] for s in all_stages]
stage_map = {s['name']: {'id': s['id'], 'sequence': s['sequence']} for s in all_stages}

neg_info = stage_map.get('Negotiation')
prop_info = stage_map.get('Proposition')
won_info = stage_map.get('Won')

negotiation_exists = neg_info is not None
negotiation_position_ok = False
negotiation_probability = None
if neg_info and prop_info and won_info:
    negotiation_position_ok = (prop_info['sequence'] < neg_info['sequence'] < won_info['sequence'])

# Get probability for Negotiation stage
if neg_info:
    neg_stage_data = ex('crm.stage', 'read', [[neg_info['id']]], {'fields': ['requirements']})
    # Probability is set per-lead in Odoo 17, but default can be read from stage
    # We check it via a test query or the stage record
    negotiation_probability = None  # Will be checked via opportunity probabilities

result['infrastructure']['negotiation_stage'] = {
    'exists': negotiation_exists,
    'position_ok': negotiation_position_ok,
    'stage_id': neg_info['id'] if neg_info else None,
    'sequence': neg_info['sequence'] if neg_info else None,
    'all_stages_ordered': stage_names_ordered,
}

# 2. Check "Gone Dark - No Response" lost reason
lr = ex('crm.lost.reason', 'search_read',
    [[['name', '=', 'Gone Dark - No Response']]], {'fields': ['id', 'name']})
result['infrastructure']['lost_reason'] = {
    'exists': len(lr) > 0,
    'id': lr[0]['id'] if lr else None,
}

# 3. Check "Strategic Accounts" sales team
sa_team = ex('crm.team', 'search_read',
    [[['name', '=', 'Strategic Accounts']]], {'fields': ['id', 'name', 'user_id']})
result['infrastructure']['sales_team'] = {
    'exists': len(sa_team) > 0,
    'id': sa_team[0]['id'] if sa_team else None,
    'leader': sa_team[0]['user_id'][1] if sa_team and sa_team[0].get('user_id') else None,
    'leader_id': sa_team[0]['user_id'][0] if sa_team and sa_team[0].get('user_id') else None,
}
sa_team_id = sa_team[0]['id'] if sa_team else None

# ========== CHECK EACH OPPORTUNITY ==========

opp_ids = seed_data.get('opportunities', {})

def get_opp_tags(lead_data):
    tag_ids = lead_data.get('tag_ids', [])
    if not tag_ids:
        return []
    tags = ex('crm.tag', 'read', [tag_ids], {'fields': ['name']})
    return [t['name'] for t in tags]

# Query all 12 opportunities (including active=False for lost ones)
for key, oid in opp_ids.items():
    try:
        opp_data = ex('crm.lead', 'search_read',
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
                'has_key_deal': 'Key Deal' in tag_names,
                'has_competitive': 'Competitive' in tag_names,
                'has_at_risk': 'At Risk' in tag_names,
                'is_on_sa_team': (d['team_id'][0] == sa_team_id) if d.get('team_id') and sa_team_id else False,
                'write_date': d.get('write_date', ''),
            }
        else:
            result['opportunities'][key] = {'id': oid, 'error': 'not_found'}
    except Exception as e:
        result['opportunities'][key] = {'id': oid, 'error': str(e)}
        result['errors'].append(f"Error checking {key}: {e}")

# ========== CHECK ACTIVITIES ON OPP03 AND OPP12 ==========

for opp_key in ['opp03', 'opp12']:
    oid = opp_ids.get(opp_key)
    if oid:
        try:
            activities = ex('mail.activity', 'search_read',
                [[['res_model', '=', 'crm.lead'], ['res_id', '=', oid]]],
                {'fields': ['activity_type_id', 'date_deadline', 'summary', 'user_id']})
            act_list = []
            for act in activities:
                act_list.append({
                    'type_name': act['activity_type_id'][1] if act.get('activity_type_id') else None,
                    'date_deadline': act.get('date_deadline', ''),
                    'summary': act.get('summary', ''),
                    'user_name': act['user_id'][1] if act.get('user_id') else None,
                })
            if opp_key in result['opportunities']:
                result['opportunities'][opp_key]['activities'] = act_list
        except Exception as e:
            result['errors'].append(f"Error checking {opp_key} activities: {e}")

# ========== CHECK OPP09 INTERNAL NOTES ==========

opp09_id = opp_ids.get('opp09')
if opp09_id:
    try:
        new_messages = ex('mail.message', 'search_read',
            [[['model', '=', 'crm.lead'], ['res_id', '=', opp09_id],
              ['message_type', '=', 'comment'], ['date', '>', start_dt]]],
            {'fields': ['body', 'date']})
        has_correction_note = False
        for msg in new_messages:
            body_text = re.sub('<[^>]+>', '', msg.get('body', '')).strip().lower()
            if 'corrected' in body_text or 'q1 review' in body_text or 'scope' in body_text:
                has_correction_note = True
                break
        if 'opp09' in result['opportunities']:
            result['opportunities']['opp09']['has_correction_note'] = has_correction_note
            result['opportunities']['opp09']['new_note_count'] = len(new_messages)
    except Exception as e:
        result['errors'].append(f"Error checking opp09 notes: {e}")

# ========== CHECK DUPLICATE MERGE ==========

caspian_canonical_id = seed_data['partners'].get('caspian')
caspian_dup_id = seed_data['partners'].get('caspian_dup')

# Check if duplicate is archived
if caspian_dup_id:
    try:
        dup_data = ex('res.partner', 'search_read',
            [[['id', '=', caspian_dup_id],
              '|', ['active', '=', True], ['active', '=', False]]],
            {'fields': ['name', 'active']})
        if dup_data:
            result['duplicate_merge']['duplicate_active'] = dup_data[0].get('active', True)
            result['duplicate_merge']['duplicate_name'] = dup_data[0].get('name', '')
        else:
            result['duplicate_merge']['duplicate_active'] = None
            result['duplicate_merge']['duplicate_name'] = 'not_found'
    except Exception as e:
        result['errors'].append(f"Error checking duplicate: {e}")

# Check if opp06 (API Gateway Setup) is now on canonical Caspian Technologies
opp06_id = opp_ids.get('opp06')
if opp06_id and caspian_canonical_id:
    opp06_data = result['opportunities'].get('opp06', {})
    result['duplicate_merge']['opp06_partner_id'] = opp06_data.get('partner_id')
    result['duplicate_merge']['opp06_on_canonical'] = (opp06_data.get('partner_id') == caspian_canonical_id)
    result['duplicate_merge']['canonical_id'] = caspian_canonical_id

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
