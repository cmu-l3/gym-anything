#!/bin/bash
echo "=== Exporting account_consolidation Result ==="

source /workspace/scripts/task_utils.sh

if ! type odoo_db_query &>/dev/null; then
    odoo_db_query() {
        docker exec odoo-db psql -U odoo -d odoodb -t -A -c "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || \
        DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/account_consolidation_end.png

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

# Load seed IDs
try:
    with open('/tmp/account_consolidation_ids.json') as f:
        seed_data = json.load(f)
    company_a_id = seed_data['company_a_id']
    company_b_id = seed_data['company_b_id']
    contact_a_ids = seed_data['contact_a_ids']
    contact_b_ids = seed_data['contact_b_ids']
    opp_a_ids = seed_data['opp_a_ids']
    opp_b_id = seed_data['opp_b_id']
    cat_id = seed_data['cat_id']
except Exception as e:
    print(f"FATAL: Cannot load seed IDs: {e}")
    import sys; sys.exit(1)

task_start_ts = int(open('/tmp/task_start_timestamp').read().strip())
start_dt = datetime.fromtimestamp(task_start_ts).strftime('%Y-%m-%d %H:%M:%S')

result = {
    'company_a_id': company_a_id,
    'company_b_id': company_b_id,
    'contacts': {},
    'opportunities': {},
    'company_a_active': None,
    'company_b_new_note': False,
    'company_b_has_dedup_tag': None,
    'task_start_dt': start_dt,
}

# --- Check contacts: where is each contact's parent_id? ---
all_contact_ids = {}
all_contact_ids.update(contact_a_ids)
all_contact_ids.update(contact_b_ids)

for name, cid in all_contact_ids.items():
    contact_data = models.execute_kw(DB, uid, PASS, 'res.partner', 'read',
        [[cid]], {'fields': ['name', 'parent_id', 'active']})[0]
    result['contacts'][name] = {
        'id': cid,
        'parent_id': contact_data['parent_id'][0] if contact_data.get('parent_id') else None,
        'parent_name': contact_data['parent_id'][1] if contact_data.get('parent_id') else None,
        'active': contact_data.get('active', True),
        'on_primary': contact_data['parent_id'][0] == company_b_id if contact_data.get('parent_id') else False,
    }

# --- Check opportunities: what partner_id do they have? ---
all_opp_ids = dict(opp_a_ids)
all_opp_ids['Meridian Annual License'] = opp_b_id

for name, oid in all_opp_ids.items():
    opp_data = models.execute_kw(DB, uid, PASS, 'crm.lead', 'read',
        [[oid]], {'fields': ['name', 'partner_id', 'tag_ids', 'active']})[0]
    tag_names = []
    if opp_data.get('tag_ids'):
        tags = models.execute_kw(DB, uid, PASS, 'crm.tag', 'read',
            [opp_data['tag_ids']], {'fields': ['name']})
        tag_names = [t['name'] for t in tags]
    result['opportunities'][name] = {
        'id': oid,
        'partner_id': opp_data['partner_id'][0] if opp_data.get('partner_id') else None,
        'partner_name': opp_data['partner_id'][1] if opp_data.get('partner_id') else None,
        'on_primary': opp_data['partner_id'][0] == company_b_id if opp_data.get('partner_id') else False,
        'tag_names': tag_names,
        'has_deduped_tag': 'Account-Deduped' in tag_names,
        'active': opp_data.get('active', True),
    }

# --- Check Company A active status (should be archived) ---
company_a_data = models.execute_kw(DB, uid, PASS, 'res.partner', 'read',
    [[company_a_id]], {'fields': ['name', 'active']})[0]
result['company_a_active'] = company_a_data.get('active', True)

# --- Check Company B for new notes posted after task start ---
new_messages = models.execute_kw(DB, uid, PASS, 'mail.message', 'search_read',
    [[['model', '=', 'res.partner'], ['res_id', '=', company_b_id],
      ['message_type', '=', 'comment'], ['date', '>', start_dt]]],
    {'fields': ['body', 'date']})

has_new_note = False
for msg in new_messages:
    body_text = re.sub('<[^>]+>', '', msg.get('body', '')).strip()
    if len(body_text) > 30:
        has_new_note = True
        break
result['company_b_new_note'] = has_new_note
result['company_b_new_note_count'] = len(new_messages)

# --- Check Requires-Deduplication tag on Company B ---
company_b_data = models.execute_kw(DB, uid, PASS, 'res.partner', 'read',
    [[company_b_id]], {'fields': ['name', 'active', 'category_id']})[0]
cat_ids_on_b = company_b_data.get('category_id', [])
cat_names_on_b = []
if cat_ids_on_b:
    cats = models.execute_kw(DB, uid, PASS, 'res.partner.category', 'read',
        [cat_ids_on_b], {'fields': ['name']})
    cat_names_on_b = [c['name'] for c in cats]
result['company_b_has_dedup_tag'] = 'Requires-Deduplication' in cat_names_on_b
result['company_b_category_names'] = cat_names_on_b

with open('/tmp/account_consolidation_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
