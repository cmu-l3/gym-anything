#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Segment Opportunities by Region ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed data via Python
# We create:
# 1. Tags
# 2. Partners in BE and US
# 3. Opportunities linked to those partners
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, passwd, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure Tags Exist (and get IDs)
    # Check if they exist first to avoid duplicates if script runs twice
    tag_eu_ids = models.execute_kw(db, uid, passwd, 'crm.tag', 'search', [[['name', '=', 'Region: Europe']]])
    if not tag_eu_ids:
        tag_eu_id = models.execute_kw(db, uid, passwd, 'crm.tag', 'create', [{'name': 'Region: Europe', 'color': 1}])
    else:
        tag_eu_id = tag_eu_ids[0]

    tag_na_ids = models.execute_kw(db, uid, passwd, 'crm.tag', 'search', [[['name', '=', 'Region: North America']]])
    if not tag_na_ids:
        tag_na_id = models.execute_kw(db, uid, passwd, 'crm.tag', 'create', [{'name': 'Region: North America', 'color': 2}])
    else:
        tag_na_id = tag_na_ids[0]
    
    print(f"Tags ready: Europe={tag_eu_id}, NA={tag_na_id}")

    # 2. Get Country IDs
    be_ids = models.execute_kw(db, uid, passwd, 'res.country', 'search', [[['code', '=', 'BE']]])
    us_ids = models.execute_kw(db, uid, passwd, 'res.country', 'search', [[['code', '=', 'US']]])
    
    if not be_ids or not us_ids:
        print("Error: Could not find country codes for BE or US")
        sys.exit(1)
        
    be_id = be_ids[0]
    us_id = us_ids[0]

    # 3. Create Partners
    # We create unique partners to avoid confusion with existing demo data
    partners_data = [
        {'name': 'Brussels Waffles Inc', 'country_id': be_id, 'city': 'Brussels', 'email': 'info@waffles.be'},
        {'name': 'Antwerp Logistics', 'country_id': be_id, 'city': 'Antwerp', 'email': 'support@antwerplog.be'},
        {'name': 'Silicon Valley Tech', 'country_id': us_id, 'city': 'San Francisco', 'email': 'hello@svtech.com'},
        {'name': 'Austin Motors', 'country_id': us_id, 'city': 'Austin', 'email': 'sales@austinmotors.com'}
    ]

    partner_ids = []
    for p in partners_data:
        # Check if partner exists to avoid duplication
        existing = models.execute_kw(db, uid, passwd, 'res.partner', 'search', [[['name', '=', p['name']]]])
        if existing:
             # Clean up old partner to start fresh (ensures no pre-existing tags on their opps if we recreated opps)
             models.execute_kw(db, uid, passwd, 'res.partner', 'unlink', [existing])
        
        pid = models.execute_kw(db, uid, passwd, 'res.partner', 'create', [p])
        partner_ids.append(pid)

    # 4. Create Opportunities linked to these partners
    # Clean up old opps with these names first
    opp_names = [
        'Waffle Iron Bulk Order',
        'Logistics Software Upgrade',
        'Cloud Server Migration',
        'Fleet Tracking System'
    ]
    
    existing_opps = models.execute_kw(db, uid, passwd, 'crm.lead', 'search', [[['name', 'in', opp_names]]])
    if existing_opps:
        models.execute_kw(db, uid, passwd, 'crm.lead', 'unlink', [existing_opps])

    opps = [
        {'name': 'Waffle Iron Bulk Order', 'partner_id': partner_ids[0], 'expected_revenue': 5000, 'type': 'opportunity'},
        {'name': 'Logistics Software Upgrade', 'partner_id': partner_ids[1], 'expected_revenue': 12000, 'type': 'opportunity'},
        {'name': 'Cloud Server Migration', 'partner_id': partner_ids[2], 'expected_revenue': 45000, 'type': 'opportunity'},
        {'name': 'Fleet Tracking System', 'partner_id': partner_ids[3], 'expected_revenue': 22000, 'type': 'opportunity'}
    ]

    for opp in opps:
        models.execute_kw(db, uid, passwd, 'crm.lead', 'create', [opp])

    print("Seeded 4 opportunities with specific countries.")

except Exception as e:
    print(f"Error in setup script: {e}")
    sys.exit(1)
PYEOF

# Ensure Odoo is running and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="