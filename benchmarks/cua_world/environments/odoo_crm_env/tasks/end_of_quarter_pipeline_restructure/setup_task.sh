#!/bin/bash
set -e
echo "=== Setting up task: end_of_quarter_pipeline_restructure ==="

source /workspace/scripts/task_utils.sh

wait_for_odoo

# Seed all data via Python/XML-RPC
python3 - <<'PYEOF'
import xmlrpc.client
import json
import sys

URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    if not uid:
        print("ERROR: Authentication failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
    print(f"Authenticated as UID={uid}")
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

def ex(model, method, args, kwargs=None):
    return models.execute_kw(DB, uid, PASS, model, method, args, kwargs or {})

# ========== CLEANUP FROM PREVIOUS RUNS ==========

# Clean up opportunities created by this task
opp_names = [
    "Enterprise Data Platform",
    "Cloud Security Assessment",
    "IT Infrastructure Modernization",
    "Annual Support Renewal",
    "AI/ML Pipeline Integration",
    "API Gateway Setup",
    "Marketing Automation Platform",
    "ERP System Upgrade",
    "Employee Portal Development",
    "Employee Portal - Phase 1",
    "IoT Fleet Management",
    "DevOps Pipeline Automation",
    "Business Intelligence Dashboard",
]
for name in opp_names:
    existing = ex('crm.lead', 'search',
        [[['name', '=', name], '|', ['active', '=', True], ['active', '=', False]]])
    if existing:
        # Remove activities first
        for oid in existing:
            activities = ex('mail.activity', 'search',
                [[['res_model', '=', 'crm.lead'], ['res_id', '=', oid]]])
            if activities:
                ex('mail.activity', 'unlink', [activities])
        ex('crm.lead', 'unlink', [existing])
        print(f"Cleaned up opportunity: {name}")

# Clean up partner companies created by this task
partner_names = [
    "Apex Global Industries",
    "Boreal Systems Ltd",
    "Caspian Technologies",
    "Caspian Tech",
    "Dawnlight Digital",
    "Evergreen Solutions",
    "Falcon Dynamics",
    "Granite Peak Software",
    "Highland Analytics",
]
for name in partner_names:
    existing = ex('res.partner', 'search',
        [[['name', '=', name], ['is_company', '=', True],
          '|', ['active', '=', True], ['active', '=', False]]])
    if existing:
        # Detach children first
        children = ex('res.partner', 'search',
            [[['parent_id', 'in', existing],
              '|', ['active', '=', True], ['active', '=', False]]])
        if children:
            ex('res.partner', 'write', [children, {'parent_id': False, 'active': True}])
        ex('res.partner', 'write', [existing, {'active': False}])
        print(f"Archived partner: {name}")

# Clean up "Negotiation" stage from previous runs
neg_stages = ex('crm.stage', 'search', [[['name', '=', 'Negotiation']]])
if neg_stages:
    leads_in_neg = ex('crm.lead', 'search', [[['stage_id', 'in', neg_stages]]])
    if leads_in_neg:
        new_stage = ex('crm.stage', 'search', [[['name', '=', 'New']]], {'limit': 1})
        if new_stage:
            ex('crm.lead', 'write', [leads_in_neg, {'stage_id': new_stage[0]}])
    ex('crm.stage', 'unlink', [neg_stages])
    print("Removed existing Negotiation stage")

# Clean up lost reason
lr_ids = ex('crm.lost.reason', 'search', [[['name', '=', 'Gone Dark - No Response']]])
if lr_ids:
    ex('crm.lost.reason', 'unlink', [lr_ids])
    print("Removed existing 'Gone Dark - No Response' lost reason")

# Clean up "Strategic Accounts" sales team
sa_teams = ex('crm.team', 'search', [[['name', '=', 'Strategic Accounts']]])
if sa_teams:
    ex('crm.team', 'unlink', [sa_teams])
    print("Removed existing 'Strategic Accounts' team")

# Clean up tags
for tag_name in ['Q1-Reviewed', 'Key Deal', 'Competitive', 'At Risk']:
    tag_ids = ex('crm.tag', 'search', [[['name', '=', tag_name]]])
    if tag_ids:
        ex('crm.tag', 'unlink', [tag_ids])
        print(f"Removed tag: {tag_name}")

# ========== GET STAGE IDS ==========

stages = ex('crm.stage', 'search_read',
    [[]], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
stage_map = {s['name']: s['id'] for s in stages}
print(f"Available stages: {stage_map}")

new_stage_id = stage_map.get('New')
qualified_stage_id = stage_map.get('Qualified')
proposition_stage_id = stage_map.get('Proposition')
won_stage_id = stage_map.get('Won')

if not all([new_stage_id, qualified_stage_id, proposition_stage_id]):
    print(f"ERROR: Missing required stages. Found: {stage_map}")
    sys.exit(1)

# ========== CREATE PARTNER COMPANIES ==========

def create_partner(name, email, phone, city, street, country_code='US'):
    """Create company partner, return ID."""
    country = ex('res.country', 'search', [[['code', '=', country_code]]], {'limit': 1})
    country_id = country[0] if country else False
    vals = {
        'name': name,
        'is_company': True,
        'email': email,
        'phone': phone,
        'city': city,
        'street': street,
        'country_id': country_id,
        'active': True,
    }
    pid = ex('res.partner', 'create', [vals])
    print(f"Created partner: {name} (ID={pid})")
    return pid

partners = {}

partners['apex'] = create_partner(
    "Apex Global Industries",
    "info@apexglobal.example.com",
    "+1 (212) 555-0310",
    "New York",
    "350 Fifth Avenue, Suite 4200"
)

partners['boreal'] = create_partner(
    "Boreal Systems Ltd",
    "contact@borealsystems.example.com",
    "+1 (416) 555-0280",
    "Toronto",
    "100 King Street West, Suite 3400",
    country_code='CA'
)

partners['caspian'] = create_partner(
    "Caspian Technologies",
    "info@caspiantech.example.com",
    "+1 (415) 555-0195",
    "San Francisco",
    "525 Market Street, Suite 3100"
)

# Duplicate company (intentionally similar name, no phone)
partners['caspian_dup'] = create_partner(
    "Caspian Tech",
    "sales@caspiantech.example.com",
    "",
    "San Francisco",
    ""
)

partners['dawnlight'] = create_partner(
    "Dawnlight Digital",
    "hello@dawnlightdigital.example.com",
    "+1 (312) 555-0233",
    "Chicago",
    "233 South Wacker Drive, Suite 1800"
)

partners['evergreen'] = create_partner(
    "Evergreen Solutions",
    "enquiries@evergreensolutions.example.com",
    "+44 20 7946 0958",
    "London",
    "1 Canada Square, Level 28",
    country_code='GB'
)

partners['falcon'] = create_partner(
    "Falcon Dynamics",
    "kontakt@falcondynamics.example.com",
    "+49 89 555 0167",
    "Munich",
    "Leopoldstrasse 244",
    country_code='DE'
)

partners['granite'] = create_partner(
    "Granite Peak Software",
    "info@granitepeaksw.example.com",
    "+1 (512) 555-0142",
    "Austin",
    "100 Congress Avenue, Suite 2000"
)

partners['highland'] = create_partner(
    "Highland Analytics",
    "contact@highlandanalytics.example.com",
    "+1 (206) 555-0119",
    "Seattle",
    "1201 Third Avenue, Suite 800"
)

# ========== CREATE OPPORTUNITIES WITH INTERNAL NOTES ==========

seed_ids = {'partners': partners, 'opportunities': {}}

# --- Opp 1: Enterprise Data Platform ---
opp01_id = ex('crm.lead', 'create', [{
    'name': 'Enterprise Data Platform',
    'partner_id': partners['apex'],
    'type': 'opportunity',
    'expected_revenue': 180000,
    'stage_id': proposition_stage_id,
    'probability': 65,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp01_id], {
    'body': '<p>Met with CTO Laura Chen on 2/15. Very positive technical evaluation. Budget of $200K has been approved by the CFO for this fiscal year. Awaiting legal review of MSA before we can proceed to contract stage. Primary contact remains Laura for all technical discussions.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp01'] = opp01_id
print(f"Created Opp01: Enterprise Data Platform (ID={opp01_id})")

# --- Opp 2: Cloud Security Assessment ---
opp02_id = ex('crm.lead', 'create', [{
    'name': 'Cloud Security Assessment',
    'partner_id': partners['apex'],
    'type': 'opportunity',
    'expected_revenue': 45000,
    'stage_id': new_stage_id,
    'probability': 8,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp02_id], {
    'body': '<p>Initial discovery call on 2/28 showed limited interest from their security team. They already have an incumbent vendor. Competitor RivalSoft is also actively engaged with their CISO on a similar assessment package. Low probability of conversion at this point.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp02'] = opp02_id
print(f"Created Opp02: Cloud Security Assessment (ID={opp02_id})")

# --- Opp 3: IT Infrastructure Modernization ---
opp03_id = ex('crm.lead', 'create', [{
    'name': 'IT Infrastructure Modernization',
    'partner_id': partners['boreal'],
    'type': 'opportunity',
    'expected_revenue': 220000,
    'stage_id': qualified_stage_id,
    'probability': 40,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp03_id], {
    'body': '<p>CRITICAL UPDATE (3/5/2026): Our deal champion Sarah Chen, VP of IT Infrastructure, has confirmed she is leaving the company effective end of March. She accepted a position at another firm. We have no established relationship with her replacement. Need to identify and engage a new sponsor urgently before the transition happens.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp03'] = opp03_id
print(f"Created Opp03: IT Infrastructure Modernization (ID={opp03_id})")

# --- Opp 4: Annual Support Renewal ---
opp04_id = ex('crm.lead', 'create', [{
    'name': 'Annual Support Renewal',
    'partner_id': partners['boreal'],
    'type': 'opportunity',
    'expected_revenue': 32000,
    'stage_id': won_stage_id,
    'probability': 100,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp04_id], {
    'body': '<p>Auto-renewal confirmed via email on 2/10. Contract extends for another 12 months under existing terms. No action needed - billing will process automatically on the renewal date.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp04'] = opp04_id
print(f"Created Opp04: Annual Support Renewal (ID={opp04_id})")

# --- Opp 5: AI/ML Pipeline Integration ---
opp05_id = ex('crm.lead', 'create', [{
    'name': 'AI/ML Pipeline Integration',
    'partner_id': partners['caspian'],
    'type': 'opportunity',
    'expected_revenue': 95000,
    'stage_id': qualified_stage_id,
    'probability': 55,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp05_id], {
    'body': '<p>Technical POC completed successfully on 3/1. Their data engineering team was impressed with the integration speed. Decision expected by end of month. Main blocker is internal budget approval process which requires VP sign-off for anything over $50K.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp05'] = opp05_id
print(f"Created Opp05: AI/ML Pipeline Integration (ID={opp05_id})")

# --- Opp 6: API Gateway Setup (on DUPLICATE company) ---
opp06_id = ex('crm.lead', 'create', [{
    'name': 'API Gateway Setup',
    'partner_id': partners['caspian_dup'],
    'type': 'opportunity',
    'expected_revenue': 38000,
    'stage_id': new_stage_id,
    'probability': 10,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp06_id], {
    'body': '<p>Referred by existing client on 2/20. Had a brief intro call but prospect was non-committal. Not yet qualified - need to schedule a proper discovery session to understand requirements and timeline.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp06'] = opp06_id
print(f"Created Opp06: API Gateway Setup (ID={opp06_id})")

# --- Opp 7: Marketing Automation Platform ---
opp07_id = ex('crm.lead', 'create', [{
    'name': 'Marketing Automation Platform',
    'partner_id': partners['dawnlight'],
    'type': 'opportunity',
    'expected_revenue': 150000,
    'stage_id': proposition_stage_id,
    'probability': 70,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp07_id], {
    'body': '<p>Strong meeting with CMO Jessica Park on 3/8. Verbal commitment received on our proposal. Currently negotiating payment terms - they prefer quarterly billing. However, RivalSoft has offered them a 15% discount on a competing platform. We need to prepare a value justification document to counter their pricing pressure.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp07'] = opp07_id
print(f"Created Opp07: Marketing Automation Platform (ID={opp07_id})")

# --- Opp 8: ERP System Upgrade ---
opp08_id = ex('crm.lead', 'create', [{
    'name': 'ERP System Upgrade',
    'partner_id': partners['evergreen'],
    'type': 'opportunity',
    'expected_revenue': 310000,
    'stage_id': qualified_stage_id,
    'probability': 35,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp08_id], {
    'body': '<p>Complex multi-stakeholder deal. CTO Marcus Webb is our champion but the CEO remains skeptical about the migration timeline. RivalSoft is also being evaluated - they presented to the board last week. Our technical advantage is in the data migration tooling but we need to address their concerns about the 6-month implementation window.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp08'] = opp08_id
print(f"Created Opp08: ERP System Upgrade (ID={opp08_id})")

# --- Opp 9: Employee Portal Development ---
opp09_id = ex('crm.lead', 'create', [{
    'name': 'Employee Portal Development',
    'partner_id': partners['evergreen'],
    'type': 'opportunity',
    'expected_revenue': 55000,
    'stage_id': proposition_stage_id,
    'probability': 50,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp09_id], {
    'body': '<p>Scope creep concerns raised during 3/3 review meeting. The project has expanded beyond the original brief. Original quote was $40,000 for core portal functionality. Additional modules (SSO integration, mobile app) were added without formal change order. Need to realign with customer expectations and revert to original scope to maintain margin.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp09'] = opp09_id
print(f"Created Opp09: Employee Portal Development (ID={opp09_id})")

# --- Opp 10: IoT Fleet Management ---
opp10_id = ex('crm.lead', 'create', [{
    'name': 'IoT Fleet Management',
    'partner_id': partners['falcon'],
    'type': 'opportunity',
    'expected_revenue': 125000,
    'stage_id': new_stage_id,
    'probability': 25,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp10_id], {
    'body': '<p>Initial requirements gathering completed on 3/10. Strong product fit with our IoT module. Their VP of Operations is enthusiastic about the fleet tracking capabilities. Next step is a technical deep-dive scheduled for late March. No significant competition identified at this stage.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp10'] = opp10_id
print(f"Created Opp10: IoT Fleet Management (ID={opp10_id})")

# --- Opp 11: DevOps Pipeline Automation ---
opp11_id = ex('crm.lead', 'create', [{
    'name': 'DevOps Pipeline Automation',
    'partner_id': partners['granite'],
    'type': 'opportunity',
    'expected_revenue': 88000,
    'stage_id': qualified_stage_id,
    'probability': 45,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp11_id], {
    'body': '<p>Technical team at Granite Peak is very enthusiastic about our CI/CD integration capabilities. Budget cycle starts April 1 so timing is good. Note: RivalSoft previously lost a deal with this client two years ago due to poor support response times - this works in our favor. Engineering lead wants to do a POC in early April.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp11'] = opp11_id
print(f"Created Opp11: DevOps Pipeline Automation (ID={opp11_id})")

# --- Opp 12: Business Intelligence Dashboard ---
opp12_id = ex('crm.lead', 'create', [{
    'name': 'Business Intelligence Dashboard',
    'partner_id': partners['highland'],
    'type': 'opportunity',
    'expected_revenue': 72000,
    'stage_id': proposition_stage_id,
    'probability': 60,
    'active': True,
}])
ex('crm.lead', 'message_post', [opp12_id], {
    'body': '<p>Demo on 3/7 went very well. Final decision is pending their board meeting on March 25. Key concern: their champion, the VP of Engineering, has announced he is departing the company next month. This is an urgent risk to the deal as he was our primary advocate. We need to establish a relationship with his successor immediately.</p>',
    'message_type': 'comment',
    'subtype_xmlid': 'mail.mt_note',
})
seed_ids['opportunities']['opp12'] = opp12_id
print(f"Created Opp12: Business Intelligence Dashboard (ID={opp12_id})")

# ========== SAVE SEED DATA ==========

with open('/tmp/eoq_restructure_ids.json', 'w') as f:
    json.dump(seed_ids, f, indent=2)
print(f"\nSeed data saved to /tmp/eoq_restructure_ids.json")
print(f"Partners: {partners}")
print(f"Opportunities: {seed_ids['opportunities']}")

PYEOF

# Record task start time AFTER seeding data
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Ensure Firefox is logged in and navigate to CRM pipeline
ensure_odoo_logged_in "${CRM_PIPELINE_URL}"
sleep 3

# Take initial screenshot
take_screenshot /tmp/eoq_restructure_start.png

echo "=== end_of_quarter_pipeline_restructure setup complete ==="
