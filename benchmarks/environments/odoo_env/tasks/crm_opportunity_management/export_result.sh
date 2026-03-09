#!/bin/bash
# Export script for crm_opportunity_management task

echo "=== Exporting crm_opportunity_management Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

if [ ! -f /tmp/crm_opportunity_setup.json ]; then
    echo "ERROR: Setup data not found"
    echo '{"error": "setup_data_missing"}' > /tmp/crm_opportunity_management_result.json
    exit 0
fi

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import date, timedelta, datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

with open('/tmp/crm_opportunity_setup.json') as f:
    setup = json.load(f)

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    result = {'error': f'Cannot connect: {e}'}
    with open('/tmp/crm_opportunity_management_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

company_id = setup['company_id']
stale_id = setup['stale_opportunity_id']
active_id = setup['active_opportunity_id']
target_revenue = setup['target_expected_revenue']

# ─── Query stale opportunity current state ────────────────────────────────────
try:
    stale_opps = execute('crm.lead', 'search_read',
        [[['id', '=', stale_id]]],
        {'fields': ['id', 'name', 'active', 'stage_id', 'probability',
                    'lost_reason_id', 'type'], 'context': {'active_test': False}})
    stale = stale_opps[0] if stale_opps else {}
except Exception as e:
    stale = {}
    print(f"Warning: Could not query stale opp: {e}", file=sys.stderr)

# Check if stale opportunity was marked as lost
stale_is_inactive = not stale.get('active', True)
stale_has_lost_reason = bool(stale.get('lost_reason_id'))
stale_marked_lost = stale_is_inactive or stale.get('probability', 100) == 0

# ─── Query active opportunity current state ───────────────────────────────────
try:
    active_opps = execute('crm.lead', 'search_read',
        [[['id', '=', active_id]]],
        {'fields': ['id', 'name', 'active', 'stage_id', 'expected_revenue',
                    'probability', 'type']})
    active = active_opps[0] if active_opps else {}
except Exception as e:
    active = {}
    print(f"Warning: Could not query active opp: {e}", file=sys.stderr)

# Check stage advancement
active_stage_id = active.get('stage_id', [None, ''])[0] if isinstance(active.get('stage_id'), list) else None
active_stage_name = active.get('stage_id', [None, ''])[1] if isinstance(active.get('stage_id'), list) else ''
target_stage_id = setup.get('target_stage_id')

stage_advanced = (active_stage_id == target_stage_id) if target_stage_id else (
    'proposit' in active_stage_name.lower()
)

# Revenue set correctly
active_revenue = float(active.get('expected_revenue', 0))
revenue_correct = abs(active_revenue - target_revenue) < 1.0

# ─── Check for scheduled activities ──────────────────────────────────────────
try:
    activities = execute('mail.activity', 'search_read',
        [[['res_model', '=', 'crm.lead'], ['res_id', '=', active_id]]],
        {'fields': ['id', 'summary', 'activity_type_id', 'date_deadline', 'note']})
except Exception as e:
    activities = []
    print(f"Warning: Could not query activities: {e}", file=sys.stderr)

# Check activity: phone call, within ~10 days
today = date.today()
target_deadline = today + timedelta(days=7)

has_phone_activity = False
has_activity_near_deadline = False
activity_title_correct = False
for act in activities:
    act_type = act.get('activity_type_id', [None, ''])[1] if isinstance(act.get('activity_type_id'), list) else ''
    act_summary = act.get('summary', '') or ''
    act_deadline_str = act.get('date_deadline', '') or ''

    is_phone = 'phone' in act_type.lower() or 'call' in act_type.lower()
    is_email_or_todo = True  # Accept any activity type

    if act_deadline_str:
        try:
            act_deadline = datetime.strptime(act_deadline_str, '%Y-%m-%d').date()
            # Within 10 days of target (7 days from today)
            if abs((act_deadline - target_deadline).days) <= 3:
                has_activity_near_deadline = True
        except Exception:
            pass

    if is_phone:
        has_phone_activity = True

    # Check if title/summary contains key words
    title_lower = act_summary.lower()
    if 'horizon' in title_lower or 'follow' in title_lower or 'call' in title_lower:
        activity_title_correct = True

has_any_activity = len(activities) > 0

# ─── Check for internal note in chatter ──────────────────────────────────────
try:
    messages = execute('mail.message', 'search_read',
        [[['model', '=', 'crm.lead'], ['res_id', '=', active_id],
          ['message_type', 'in', ['comment', 'email']]]],
        {'fields': ['id', 'body', 'message_type', 'subtype_id', 'date'],
         'order': 'id desc', 'limit': 20})
except Exception as e:
    messages = []
    print(f"Warning: Could not query messages: {e}", file=sys.stderr)

note_keyword = 'pipeline cleanup'
has_internal_note = False
for msg in messages:
    body = msg.get('body', '') or ''
    if note_keyword.lower() in body.lower() or 'cleanup' in body.lower() or 'stale' in body.lower():
        has_internal_note = True
        break

task_start = 0
try:
    with open('/tmp/task_start_timestamp') as f:
        task_start = int(f.read().strip())
except Exception:
    pass

result = {
    'task': 'crm_opportunity_management',
    'company_id': company_id,
    'company_name': setup['company_name'],
    'stale_opportunity_id': stale_id,
    'stale_is_inactive': stale_is_inactive,
    'stale_has_lost_reason': stale_has_lost_reason,
    'stale_marked_lost': stale_marked_lost,
    'active_opportunity_id': active_id,
    'active_stage_id': active_stage_id,
    'active_stage_name': active_stage_name,
    'target_stage_id': target_stage_id,
    'stage_advanced_to_proposition': stage_advanced,
    'active_revenue': active_revenue,
    'target_revenue': target_revenue,
    'revenue_correct': revenue_correct,
    'activities': [{'summary': a.get('summary'), 'type': str(a.get('activity_type_id')),
                    'deadline': a.get('date_deadline')} for a in activities],
    'has_any_activity': has_any_activity,
    'has_phone_activity': has_phone_activity,
    'has_activity_near_deadline': has_activity_near_deadline,
    'activity_title_correct': activity_title_correct,
    'has_internal_note': has_internal_note,
    'task_start': task_start,
    'export_timestamp': datetime.now().isoformat(),
}

with open('/tmp/crm_opportunity_management_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Stale opp: inactive={stale_is_inactive} | lost_reason={stale_has_lost_reason}")
print(f"Active opp: stage='{active_stage_name}' | revenue=${active_revenue:.0f} | "
      f"stage_correct={stage_advanced} | revenue_correct={revenue_correct}")
print(f"Activities: {len(activities)} total | phone={has_phone_activity} | near_deadline={has_activity_near_deadline}")
print(f"Internal note: {has_internal_note}")
PYEOF

echo "=== Export Complete ==="
