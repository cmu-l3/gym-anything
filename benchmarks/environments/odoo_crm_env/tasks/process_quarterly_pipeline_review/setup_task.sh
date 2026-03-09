#!/bin/bash
set -e
echo "=== Setting up task: process_quarterly_pipeline_review ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed data via XML-RPC
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

ODOO_URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USER, PASS, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{ODOO_URL}/xmlrpc/2/object')

    # 1. Ensure 'Too Expensive' Lost Reason exists
    reasons = models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'search', [[['name', '=', 'Too Expensive']]])
    if not reasons:
        models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'create', [{'name': 'Too Expensive'}])
        print("Created Lost Reason 'Too Expensive'")

    # 2. Ensure 'At Risk' Tag exists
    tags = models.execute_kw(DB, uid, PASS, 'crm.tag', 'search', [[['name', '=', 'At Risk']]])
    if not tags:
        models.execute_kw(DB, uid, PASS, 'crm.tag', 'create', [{'name': 'At Risk', 'color': 1}])
        print("Created Tag 'At Risk'")

    # 3. Get Stage IDs
    stages = models.execute_kw(DB, uid, PASS, 'crm.stage', 'search_read', 
        [], {'fields': ['id', 'name', 'sequence'], 'order': 'sequence'})
    
    qualified_id = next((s['id'] for s in stages if s['name'] == 'Qualified'), None)
    if not qualified_id:
        # Fallback if Qualified doesn't exist (unlikely in standard data), use 2nd stage
        qualified_id = stages[1]['id']

    # 4. Clean up existing leads with these names to prevent duplicates
    lead_names = [
        'Cloud Migration - Hyperion Systems',
        'ERP Implementation - Zenith Corp',
        'Consulting Retainer - Apex Global'
    ]
    existing_ids = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search', [[['name', 'in', lead_names]]])
    if existing_ids:
        models.execute_kw(DB, uid, PASS, 'crm.lead', 'unlink', [existing_ids])
        print(f"Cleaned up {len(existing_ids)} existing leads")

    # 5. Create Opportunities

    # Opp 1: Hyperion (To be Lost)
    models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
        'name': 'Cloud Migration - Hyperion Systems',
        'type': 'opportunity',
        'expected_revenue': 45000,
        'stage_id': qualified_id,
        'description': 'UPDATE: Client met with competitor X. They offered a 20% discount which is below our floor. We cannot match their price. Deal is likely dead.',
        'probability': 20
    }])

    # Opp 2: Zenith (To be At Risk)
    models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
        'name': 'ERP Implementation - Zenith Corp',
        'type': 'opportunity',
        'expected_revenue': 120000,
        'stage_id': qualified_id,
        'priority': '1', # Set to 1 star initially so agent has to change it to 0
        'description': 'UPDATE: Our main champion, Sarah, has left the company. The new CTO is skeptical of our timeline. We need to be careful here.',
        'probability': 40
    }])

    # Opp 3: Apex (To be Negotiation)
    models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
        'name': 'Consulting Retainer - Apex Global',
        'type': 'opportunity',
        'expected_revenue': 85000,
        'stage_id': qualified_id,
        'description': 'UPDATE: Just got off the phone. CEO gave verbal agreement to the terms. Waiting for legal to stamp the contract. We are basically there.',
        'probability': 50
    }])

    print("Seeding complete.")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is ready and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="