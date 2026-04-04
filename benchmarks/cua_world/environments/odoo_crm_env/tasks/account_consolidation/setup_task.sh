#!/bin/bash
echo "=== Setting up account_consolidation task ==="

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

wait_for_odoo

python3 - <<'PYEOF'
import xmlrpc.client
import json

URL = 'http://localhost:8069'
DB = 'odoodb'
USER = 'admin'
PASS = 'admin'

common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
uid = common.authenticate(DB, USER, PASS, {})
models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

print(f"Authenticated as UID={uid}")

# --- Clean up existing Meridian records from previous runs ---
for company_name in ['Meridian Solutions Group', 'Meridian Solutions Grp']:
    existing = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
        [[['name', '=', company_name], ['active', 'in', [True, False]]]])
    if existing:
        # Unlink contacts first to avoid FK issues
        child_ids = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
            [[['parent_id', 'in', existing], ['active', 'in', [True, False]]]])
        if child_ids:
            # Detach children before deleting parent
            models.execute_kw(DB, uid, PASS, 'res.partner', 'write',
                [child_ids, {'parent_id': False, 'active': True}])
        # Archive and unlink
        models.execute_kw(DB, uid, PASS, 'res.partner', 'write',
            [existing, {'active': False}])
        print(f"Archived old '{company_name}' records: {existing}")

# Clean up contact names
for contact_name in ['Amanda Cortez', 'Ben Holloway', 'Celia Park', 'David Osei', 'Eva Lindqvist']:
    existing_contacts = models.execute_kw(DB, uid, PASS, 'res.partner', 'search',
        [[['name', '=', contact_name], ['active', 'in', [True, False]]]])
    if existing_contacts:
        models.execute_kw(DB, uid, PASS, 'res.partner', 'write',
            [existing_contacts, {'active': False}])
        print(f"Archived old contact '{contact_name}': {existing_contacts}")

# Clean up Meridian opportunities
for opp_name in ['Meridian ERP Phase 1', 'Meridian Security Audit', 'Meridian Annual License']:
    existing_opps = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search',
        [[['name', '=', opp_name], ['active', 'in', [True, False]]]])
    if existing_opps:
        models.execute_kw(DB, uid, PASS, 'crm.lead', 'write',
            [existing_opps, {'active': False}])
        print(f"Archived old opportunity '{opp_name}': {existing_opps}")

# Clean up Account-Deduped tag
ad_tag = models.execute_kw(DB, uid, PASS, 'crm.tag', 'search',
    [[['name', '=', 'Account-Deduped']]])
if ad_tag:
    models.execute_kw(DB, uid, PASS, 'crm.tag', 'unlink', [ad_tag])
    print(f"Removed old 'Account-Deduped' tag")

# --- Get or create Requires-Deduplication partner category ---
cat_ids = models.execute_kw(DB, uid, PASS, 'res.partner.category', 'search',
    [[['name', '=', 'Requires-Deduplication']]])
if not cat_ids:
    cat_id = models.execute_kw(DB, uid, PASS, 'res.partner.category', 'create',
        [{'name': 'Requires-Deduplication'}])
    print(f"Created 'Requires-Deduplication' category ID={cat_id}")
else:
    cat_id = cat_ids[0]
    print(f"Found existing 'Requires-Deduplication' category ID={cat_id}")

# --- Get New stage for CRM ---
new_stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search_read',
    [[['name', '=', 'New']]], {'fields': ['id'], 'limit': 1})
qualified_stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search_read',
    [[['name', 'ilike', 'Qualified']]], {'fields': ['id'], 'limit': 1})
new_stage_id = new_stages[0]['id'] if new_stages else None
qualified_stage_id = qualified_stages[0]['id'] if qualified_stages else None

# --- Create Company A: "Meridian Solutions Group" (NON-primary, duplicate) ---
company_a_id = models.execute_kw(DB, uid, PASS, 'res.partner', 'create', [{
    'name': 'Meridian Solutions Group',
    'is_company': True,
    'email': 'contact@meridiansolutionsgroup.com',
    'phone': '+1-312-555-0201',
    'active': True,
    'category_id': [(4, cat_id)],
}])
print(f"Created Company A 'Meridian Solutions Group' ID={company_a_id}")

# --- Create Company B: "Meridian Solutions Grp" (PRIMARY record) ---
company_b_id = models.execute_kw(DB, uid, PASS, 'res.partner', 'create', [{
    'name': 'Meridian Solutions Grp',
    'is_company': True,
    'email': 'info@meridiansolutionsgrp.com',
    'phone': '+1-312-555-0202',
    'active': True,
    'category_id': [(4, cat_id)],
}])
print(f"Created Company B 'Meridian Solutions Grp' ID={company_b_id}")

# --- Post the PRIMARY notice note on Company B ---
models.execute_kw(DB, uid, PASS, 'res.partner', 'message_post',
    [[company_b_id]],
    {
        'body': (
            "<p>\u26a0\ufe0f DUPLICATE RECORD NOTICE: This record ('Meridian Solutions Grp') is the "
            "PRIMARY record for the Meridian account. All contacts, deals, and communications from "
            "the duplicate record ('Meridian Solutions Group') must be consolidated here. "
            "Archive the duplicate once migration is complete.</p>"
        ),
        'message_type': 'comment',
        'subtype_xmlid': 'mail.mt_note',
    })
print(f"Posted PRIMARY NOTICE note on Company B (ID={company_b_id})")

# --- Create contacts under Company A (to be moved) ---
contacts_a = [
    {'name': 'Amanda Cortez', 'function': 'VP Sales'},
    {'name': 'Ben Holloway', 'function': 'CTO'},
    {'name': 'Celia Park', 'function': 'Finance Director'},
]
contact_a_ids = {}
for c in contacts_a:
    cid = models.execute_kw(DB, uid, PASS, 'res.partner', 'create', [{
        'name': c['name'],
        'function': c['function'],
        'parent_id': company_a_id,
        'is_company': False,
        'active': True,
    }])
    contact_a_ids[c['name']] = cid
    print(f"Created contact '{c['name']}' ID={cid} under Company A")

# --- Create contacts under Company B (already on primary) ---
contacts_b = [
    {'name': 'David Osei', 'function': 'CEO'},
    {'name': 'Eva Lindqvist', 'function': 'COO'},
]
contact_b_ids = {}
for c in contacts_b:
    cid = models.execute_kw(DB, uid, PASS, 'res.partner', 'create', [{
        'name': c['name'],
        'function': c['function'],
        'parent_id': company_b_id,
        'is_company': False,
        'active': True,
    }])
    contact_b_ids[c['name']] = cid
    print(f"Created contact '{c['name']}' ID={cid} under Company B")

# --- Create opportunities ---
# 2 under Company A
opp_a_ids = {}
for opp_name, rev in [('Meridian ERP Phase 1', 65000), ('Meridian Security Audit', 28000)]:
    opp_id = models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
        'name': opp_name,
        'type': 'opportunity',
        'partner_id': company_a_id,
        'expected_revenue': rev,
        'stage_id': qualified_stage_id,
        'active': True,
    }])
    opp_a_ids[opp_name] = opp_id
    print(f"Created opportunity '{opp_name}' ID={opp_id} under Company A")

# 1 under Company B
opp_b_id = models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
    'name': 'Meridian Annual License',
    'type': 'opportunity',
    'partner_id': company_b_id,
    'expected_revenue': 42000,
    'stage_id': new_stage_id,
    'active': True,
}])
print(f"Created opportunity 'Meridian Annual License' ID={opp_b_id} under Company B")

# --- Save all IDs for export ---
seed_data = {
    'company_a_id': company_a_id,
    'company_b_id': company_b_id,
    'contact_a_ids': contact_a_ids,
    'contact_b_ids': contact_b_ids,
    'opp_a_ids': opp_a_ids,
    'opp_b_id': opp_b_id,
    'cat_id': cat_id,
}
with open('/tmp/account_consolidation_ids.json', 'w') as f:
    json.dump(seed_data, f, indent=2)

print("Seed data saved to /tmp/account_consolidation_ids.json")
print(f"Summary: Company A ID={company_a_id}, Company B ID={company_b_id}")
print(f"  Contacts under A: {contact_a_ids}")
print(f"  Contacts under B: {contact_b_ids}")
print(f"  Opps under A: {opp_a_ids}, Opp under B: {opp_b_id}")

PYEOF

date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

ensure_odoo_logged_in "${CRM_PIPELINE_URL}"
sleep 2

take_screenshot /tmp/account_consolidation_start.png
echo "=== account_consolidation setup complete ==="
