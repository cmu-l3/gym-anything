#!/bin/bash
set -e
echo "=== Setting up Regional Sales Team Assignment task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Odoo to be ready
wait_for_odoo

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Seed Data (Partners and Leads)
# We use python to inject specific scenarios into the DB via XML-RPC
python3 - <<PYEOF
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url))
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url))

    # --- Clean up previous run artifacts ---
    # Delete 'West Coast' team if it exists
    existing_teams = models.execute_kw(db, uid, password, 'crm.team', 'search', [[['name', '=', 'West Coast']]])
    if existing_teams:
        print(f"Cleaning up {len(existing_teams)} existing 'West Coast' teams...")
        models.execute_kw(db, uid, password, 'crm.team', 'unlink', [existing_teams])

    # --- Helpers ---
    def get_state_id(code, country_code='US'):
        # Find US country ID first
        us_country = models.execute_kw(db, uid, password, 'res.country', 'search', [[['code', '=', country_code]]])
        if not us_country: return False
        
        state = models.execute_kw(db, uid, password, 'res.country.state', 'search', 
            [[['code', '=', code], ['country_id', '=', us_country[0]]]])
        return state[0] if state else False

    # Get State IDs
    ca_id = get_state_id('CA')
    ny_id = get_state_id('NY')
    tx_id = get_state_id('TX')
    
    # Fallback if states not loaded (create them)
    if not ca_id:
        print("Creating CA state...")
        us_id = models.execute_kw(db, uid, password, 'res.country', 'search', [[['code', '=', 'US']]])[0]
        ca_id = models.execute_kw(db, uid, password, 'res.country.state', 'create', [{'name': 'California', 'code': 'CA', 'country_id': us_id}])
    
    if not ny_id:
        print("Creating NY state...")
        us_id = models.execute_kw(db, uid, password, 'res.country', 'search', [[['code', '=', 'US']]])[0]
        ny_id = models.execute_kw(db, uid, password, 'res.country.state', 'create', [{'name': 'New York', 'code': 'NY', 'country_id': us_id}])

    if not tx_id:
        print("Creating TX state...")
        us_id = models.execute_kw(db, uid, password, 'res.country', 'search', [[['code', '=', 'US']]])[0]
        tx_id = models.execute_kw(db, uid, password, 'res.country.state', 'create', [{'name': 'Texas', 'code': 'TX', 'country_id': us_id}])

    # --- Create Partners ---
    partners_data = [
        {'name': 'Golden Gate Software', 'state_id': ca_id, 'city': 'San Francisco', 'email': 'contact@goldengate.com'},
        {'name': 'SoCal Surf Shop', 'state_id': ca_id, 'city': 'San Diego', 'email': 'info@socalsurf.com'},
        {'name': 'Napa Valley Vineyards', 'state_id': ca_id, 'city': 'Napa', 'email': 'sales@napavine.com'},
        {'name': 'Gotham Finance', 'state_id': ny_id, 'city': 'New York', 'email': 'trade@gotham.com'},
        {'name': 'Lone Star Logistics', 'state_id': tx_id, 'city': 'Austin', 'email': 'ops@lonestar.com'}
    ]
    
    partner_ids = {}
    for p in partners_data:
        # Check existence
        existing = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', p['name']]]])
        if existing:
            pid = existing[0]
            # Ensure state is correct
            models.execute_kw(db, uid, password, 'res.partner', 'write', [pid, {'state_id': p['state_id']}])
        else:
            pid = models.execute_kw(db, uid, password, 'res.partner', 'create', [p])
        
        partner_ids[p['name']] = pid
        print(f"Partner ready: {p['name']} (ID: {pid})")

    # --- Create Opportunities ---
    # We explicitly set team_id to False or default (usually 1) to ensure they aren't pre-assigned
    sales_team_default = 1
    
    opps = [
        {
            'name': 'Golden Gate Software Upgrade', 
            'partner_id': partner_ids['Golden Gate Software'],
            'expected_revenue': 50000,
            'type': 'opportunity',
            'team_id': sales_team_default 
        },
        {
            'name': 'SoCal Surf Shop Franchise', 
            'partner_id': partner_ids['SoCal Surf Shop'],
            'expected_revenue': 12000,
            'type': 'opportunity',
            'team_id': sales_team_default
        },
        {
            'name': 'Napa Valley Logistics', 
            'partner_id': partner_ids['Napa Valley Vineyards'],
            'expected_revenue': 75000,
            'type': 'opportunity',
            'team_id': sales_team_default
        },
        {
            'name': 'Gotham Trading Platform', 
            'partner_id': partner_ids['Gotham Finance'],
            'expected_revenue': 120000,
            'type': 'opportunity',
            'team_id': sales_team_default
        },
        {
            'name': 'Austin Warehouse Automation', 
            'partner_id': partner_ids['Lone Star Logistics'],
            'expected_revenue': 45000,
            'type': 'opportunity',
            'team_id': sales_team_default
        }
    ]

    for opp in opps:
        existing = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', opp['name']]]])
        if existing:
            # Reset team to default
            models.execute_kw(db, uid, password, 'crm.lead', 'write', [existing, {'team_id': sales_team_default}])
            print(f"Reset Opportunity: {opp['name']}")
        else:
            oid = models.execute_kw(db, uid, password, 'crm.lead', 'create', [opp])
            print(f"Created Opportunity: {opp['name']} (ID: {oid})")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# 4. Open Firefox to CRM Pipeline
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"
sleep 2

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="