#!/bin/bash
set -e
echo "=== Setting up correct_marketing_attribution task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Setup Data via Python XML-RPC
# This creates the UTM tags and the 3 opportunities with empty tracking fields
python3 - <<'PYEOF'
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

    # 1. Ensure UTM Records Exist
    def get_or_create(model, name):
        ids = models.execute_kw(db, uid, password, model, 'search', [[['name', '=', name]]])
        if ids:
            return ids[0]
        return models.execute_kw(db, uid, password, model, 'create', [{'name': name}])

    camp_id = get_or_create('utm.campaign', 'Summer 2025 Promotion')
    med_id = get_or_create('utm.medium', 'Email')
    src_id = get_or_create('utm.source', 'Newsletter')
    
    print(f"UTM Setup: Camp={camp_id}, Med={med_id}, Src={src_id}")

    # 2. Create Target Opportunities (Reset if exist)
    targets = [
        {
            'name': 'Fleet Management Software - Logistics Inc',
            'partner_name': 'Logistics Inc',
            'expected_revenue': 15000,
            'probability': 20
        },
        {
            'name': 'Inventory Control System - Warehouse Co',
            'partner_name': 'Warehouse Co',
            'expected_revenue': 22000,
            'probability': 30
        },
        {
            'name': 'ERP Implementation - Manufacturing Ltd',
            'partner_name': 'Manufacturing Ltd',
            'expected_revenue': 85000,
            'probability': 10
        }
    ]

    for t in targets:
        # Check if exists
        existing = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', t['name']]]])
        
        data = t.copy()
        # Explicitly set tracking to False (Empty)
        data.update({
            'campaign_id': False,
            'medium_id': False,
            'source_id': False,
            'type': 'opportunity'
        })

        if existing:
            models.execute_kw(db, uid, password, 'crm.lead', 'write', [existing, data])
            print(f"Reset opportunity: {t['name']}")
        else:
            models.execute_kw(db, uid, password, 'crm.lead', 'create', [data])
            print(f"Created opportunity: {t['name']}")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is open and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="