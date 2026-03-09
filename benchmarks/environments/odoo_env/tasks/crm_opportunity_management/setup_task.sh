#!/bin/bash
# Setup script for crm_opportunity_management task
# Creates a company "Horizon Technologies Ltd" with 2 CRM opportunities:
#   1. A STALE opportunity (45 days old, early stage, no activity)
#   2. An ACTIVE opportunity (5 days old, Qualified stage)
# Agent must: identify stale → mark lost; update active → Proposition + activity + note

echo "=== Setting up crm_opportunity_management ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

echo "Waiting for Odoo..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done
sleep 2

python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
from datetime import date, timedelta

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    if not uid:
        print("ERROR: Authentication failed!", file=sys.stderr)
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
except Exception as e:
    print(f"ERROR: Cannot connect to Odoo: {e}", file=sys.stderr)
    sys.exit(1)

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

COMPANY_NAME = 'Horizon Technologies Ltd'

# ─── Create or find the company ──────────────────────────────────────────────
existing = execute('res.partner', 'search_read',
    [[['name', '=', COMPANY_NAME], ['is_company', '=', True]]],
    {'fields': ['id', 'name'], 'limit': 1})

if existing:
    company_id = existing[0]['id']
    print(f"Using existing company: {COMPANY_NAME} (id={company_id})")
else:
    company_id = execute('res.partner', 'create', [{
        'name': COMPANY_NAME,
        'is_company': True,
        'customer_rank': 1,
        'email': 'info@horizontech.example.com',
        'phone': '+1-415-555-0210',
        'city': 'San Francisco',
        'country_id': 233,  # USA
    }])
    print(f"Created company: {COMPANY_NAME} (id={company_id})")

# ─── Get CRM pipeline stages ─────────────────────────────────────────────────
stages = execute('crm.stage', 'search_read',
    [[['active', '=', True]]],
    {'fields': ['id', 'name', 'sequence', 'is_won'], 'order': 'sequence asc'})

stage_map = {s['name'].lower(): s for s in stages}

# Find 'New' stage (or first stage)
new_stage = None
qualified_stage = None
proposition_stage = None

for s in stages:
    name_lower = s['name'].lower()
    if not new_stage and ('new' in name_lower or s['sequence'] <= 10):
        new_stage = s
    if not qualified_stage and 'qualif' in name_lower:
        qualified_stage = s
    if not proposition_stage and ('propos' in name_lower or 'proposition' in name_lower):
        proposition_stage = s

# Fallbacks based on sequence
if not new_stage:
    new_stage = stages[0] if stages else None
if not qualified_stage and len(stages) > 1:
    qualified_stage = stages[1]
if not proposition_stage and len(stages) > 2:
    proposition_stage = stages[2]

print(f"CRM stages found: New='{new_stage['name'] if new_stage else 'N/A'}', "
      f"Qualified='{qualified_stage['name'] if qualified_stage else 'N/A'}', "
      f"Proposition='{proposition_stage['name'] if proposition_stage else 'N/A'}'")

# ─── Clean up any pre-existing Horizon Technologies opportunities ─────────────
existing_opps = execute('crm.lead', 'search_read',
    [[['partner_id', '=', company_id], ['type', '=', 'opportunity']]],
    {'fields': ['id', 'name']})

if existing_opps:
    print(f"Removing {len(existing_opps)} pre-existing opportunities for this company...")
    execute('crm.lead', 'write',
        [[o['id'] for o in existing_opps], {'active': False}])

# ─── Create STALE opportunity (45 days old, New stage) ───────────────────────
stale_stage_id = new_stage['id'] if new_stage else stages[0]['id']
stale_id = execute('crm.lead', 'create', [{
    'name': 'Legacy System Migration & Modernization',
    'partner_id': company_id,
    'type': 'opportunity',
    'stage_id': stale_stage_id,
    'expected_revenue': 28000.0,
    'probability': 10.0,
    'description': 'Initial contact made Q3. No response to follow-ups. System migration proposal sent.',
    'user_id': uid,
}])
print(f"Created stale opportunity: 'Legacy System Migration' (id={stale_id})")

# ─── Create ACTIVE opportunity (5 days old, Qualified stage) ─────────────────
active_stage_id = qualified_stage['id'] if qualified_stage else (stages[1]['id'] if len(stages) > 1 else stale_stage_id)
active_id = execute('crm.lead', 'create', [{
    'name': 'Enterprise Cloud License Renewal',
    'partner_id': company_id,
    'type': 'opportunity',
    'stage_id': active_stage_id,
    'expected_revenue': 45000.0,
    'probability': 40.0,
    'description': 'Customer contacted us about renewing their enterprise license. Demo scheduled. Good engagement.',
    'user_id': uid,
}])
print(f"Created active opportunity: 'Enterprise Cloud License Renewal' (id={active_id})")

# ─── Make the stale opportunity appear old (45 days ago) via psql ────────────
# We do this via XML-RPC by writing a custom date if supported,
# or store setup data for the verifier to work around it.
# Odoo won't allow setting create_date via ORM, so we record the expected stale date.
stale_cutoff = (date.today() - timedelta(days=30)).isoformat()

# ─── Save setup data ──────────────────────────────────────────────────────────
setup_data = {
    'company_id': company_id,
    'company_name': COMPANY_NAME,
    'stale_opportunity_id': stale_id,
    'stale_opportunity_name': 'Legacy System Migration & Modernization',
    'stale_stage_name': new_stage['name'] if new_stage else 'New',
    'active_opportunity_id': active_id,
    'active_opportunity_name': 'Enterprise Cloud License Renewal',
    'active_stage_name': qualified_stage['name'] if qualified_stage else 'Qualified',
    'target_stage_name': proposition_stage['name'] if proposition_stage else 'Proposition',
    'target_stage_id': proposition_stage['id'] if proposition_stage else None,
    'target_expected_revenue': 65000.0,
    'stale_cutoff_date': stale_cutoff,
}
with open('/tmp/crm_opportunity_setup.json', 'w') as f:
    json.dump(setup_data, f, indent=2)

print(f"\n=== Setup Summary ===")
print(f"Company:            {COMPANY_NAME}")
print(f"Stale opportunity:  'Legacy System Migration' — stage: {setup_data['stale_stage_name']}")
print(f"Active opportunity: 'Enterprise Cloud License Renewal' — stage: {setup_data['active_stage_name']}")
print(f"Target (active):    advance to '{setup_data['target_stage_name']}', revenue=$65,000, + activity + note")
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Python setup script failed!"
    exit 1
fi

# ─── Make the stale opportunity appear 45 days old via direct DB ─────────────
STALE_ID=$(python3 -c "import json; d=json.load(open('/tmp/crm_opportunity_setup.json')); print(d['stale_opportunity_id'])")
echo "Setting stale opportunity (id=$STALE_ID) create/write date to 45 days ago..."

docker exec odoo-postgres psql -U odoo odoo_demo -c \
    "UPDATE crm_lead SET create_date = NOW() - INTERVAL '45 days', write_date = NOW() - INTERVAL '45 days' WHERE id = $STALE_ID;" \
    2>/dev/null || echo "Warning: Could not update stale date via psql"

# ─── Record task start timestamp ─────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp

# ─── Ensure Firefox is open ───────────────────────────────────────────────────
FIREFOX_PID=$(pgrep -f firefox 2>/dev/null | head -1)
if [ -z "$FIREFOX_PID" ]; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/odoo/crm' &" 2>/dev/null
    sleep 5
fi

sleep 2
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Company: Horizon Technologies Ltd"
echo "Setup data: /tmp/crm_opportunity_setup.json"
