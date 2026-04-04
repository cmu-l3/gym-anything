#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Split Pipeline Stage ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed data via Python/XML-RPC
python3 - << 'PYEOF'
import xmlrpc.client
import random
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

# 1. Ensure 'Proposition' stage exists and is clean
# Find "Proposition" or "Proposition (Draft)"/Final from previous runs to reset
stages = models.execute_kw(db, uid, password, 'crm.stage', 'search_read',
    [[['name', 'ilike', 'Proposition']]], {'fields': ['id', 'name']})

prop_stage_id = None

# Clean up previous runs if necessary
for s in stages:
    if s['name'] == 'Proposition':
        prop_stage_id = s['id']
    elif 'Draft' in s['name'] or 'Final' in s['name']:
        # Try to rename one back to Proposition and delete the other
        if not prop_stage_id:
            models.execute_kw(db, uid, password, 'crm.stage', 'write', [[s['id']], {'name': 'Proposition'}])
            prop_stage_id = s['id']
        else:
            models.execute_kw(db, uid, password, 'crm.stage', 'unlink', [[s['id']]])

if not prop_stage_id:
    # Create if missing
    print("Creating Proposition stage...")
    prop_stage_id = models.execute_kw(db, uid, password, 'crm.stage', 'create', [{
        'name': 'Proposition',
        'sequence': 15, 
    }])

# 2. Clear existing leads in this stage to ensure clean slate
existing_leads = models.execute_kw(db, uid, password, 'crm.lead', 'search',
    [[['stage_id', '=', prop_stage_id]]])
if existing_leads:
    models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_leads])

# 3. Seed Opportunities
# High Probability (>70%) - Should be moved
high_prob_leads = [
    ("Global Logistics Contract", 90.0, "Logistics Inc"),
    ("Enterprise License Upgrade", 85.0, "TechFlow Systems"),
    ("Q3 Managed Services", 75.0, "Apex Media")
]

# Low Probability (<=70%) - Should stay
low_prob_leads = [
    ("Office Expansion Inquiry", 40.0, "NorthStar Realty"),
    ("Initial Consultation", 50.0, "SmallBiz Solutions"),
    ("Hardware Refresh Estimate", 65.0, "CompuServe Local")
]

# Create Partner helper
def get_or_create_partner(name):
    p = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
    if p: return p[0]
    return models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': name, 'is_company': True}])

print("Seeding leads...")

# Create High Prob
for name, prob, partner in high_prob_leads:
    pid = get_or_create_partner(partner)
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': name,
        'partner_id': pid,
        'stage_id': prop_stage_id,
        'probability': prob,
        'expected_revenue': random.randint(10000, 50000),
        'type': 'opportunity'
    }])

# Create Low Prob
for name, prob, partner in low_prob_leads:
    pid = get_or_create_partner(partner)
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': name,
        'partner_id': pid,
        'stage_id': prop_stage_id,
        'probability': prob,
        'expected_revenue': random.randint(2000, 8000),
        'type': 'opportunity'
    }])

print("Data seeding complete.")
PYEOF

# Ensure Firefox is fresh and logged in
pkill -f firefox || true
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="