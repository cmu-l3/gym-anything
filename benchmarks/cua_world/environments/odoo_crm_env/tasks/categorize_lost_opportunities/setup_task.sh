#!/bin/bash
set -e
echo "=== Setting up task: categorize_lost_opportunities ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo
wait_for_odoo

# Create Python seeding script
cat > /tmp/seed_lost_data.py << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = "http://localhost:8069"
DB = "odoodb"
USER = "admin"
PASS = "admin"

def seed():
    try:
        # Connect
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USER, PASS, {})
        if not uid:
            print("Auth failed")
            sys.exit(1)
        
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

        # 1. Create Lost Reasons
        reasons = ['Price too high', 'Budget Freeze', 'Lacking Features']
        for name in reasons:
            ids = models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'search', [[['name', '=', name]]])
            if not ids:
                models.execute_kw(DB, uid, PASS, 'crm.lost.reason', 'create', [{'name': name}])
                print(f"Created reason: {name}")

        # 2. Create Opportunities
        # format: (Name, Partner, Note, [Implicit Reason - not set yet])
        opps = [
            (
                "Enterprise License - Summit Financial",
                "Summit Financial",
                "I spoke with the purchasing manager today. Unfortunately, they decided to go with Competitor X because they offered a 25% discount on the licensing fees. We tried to negotiate, but we just couldn't match their pricing structure."
            ),
            (
                "Fleet Tracking System - BlueWave Logistics",
                "BlueWave Logistics",
                "The demo went well, but their technical team rejected our solution. They absolutely require offline map caching for drivers in remote areas, and our current mobile app does not support this feature."
            ),
            (
                "Cloud Storage Migration - Apex Healthcare",
                "Apex Healthcare",
                "Bad news - the project is off. The CFO just announced a freeze on all new IT procurement for the rest of the year due to Q3 revenue shortfalls. They have zero budget to move forward right now."
            )
        ]

        for name, partner, note in opps:
            # Check existence (active or inactive)
            existing = models.execute_kw(DB, uid, PASS, 'crm.lead', 'search', 
                [[['name', '=', name], '|', ['active', '=', True], ['active', '=', False]]])
            
            if existing:
                # Reset existing
                models.execute_kw(DB, uid, PASS, 'crm.lead', 'write', [existing, {
                    'active': False,
                    'probability': 0,
                    'lost_reason_id': False # Clear reason
                }])
                print(f"Reset opportunity: {name}")
                lead_id = existing[0]
            else:
                # Create new
                lead_id = models.execute_kw(DB, uid, PASS, 'crm.lead', 'create', [{
                    'name': name,
                    'partner_name': partner,
                    'type': 'opportunity',
                    'probability': 20
                }])
                print(f"Created opportunity: {name}")

            # Post Note (if not already present ideally, but duplicate note is fine for context)
            # We'll post it to ensure it's at the top/recent
            models.execute_kw(DB, uid, PASS, 'crm.lead', 'message_post', [lead_id], {
                'body': note,
                'message_type': 'comment',
                'subtype_xmlid': 'mail.mt_note'
            })

            # Ensure it is Lost
            models.execute_kw(DB, uid, PASS, 'crm.lead', 'write', [[lead_id], {
                'active': False,
                'probability': 0,
                'lost_reason_id': False
            }])

    except Exception as e:
        print(f"Error seeding data: {e}")
        sys.exit(1)

seed()
PYEOF

# Run seeding
python3 /tmp/seed_lost_data.py

# Launch Firefox and login
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="