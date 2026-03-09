#!/bin/bash
set -e
echo "=== Setting up create_crm_salesperson task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Prepare Database State:
# 1. Ensure "Direct Sales" team exists
# 2. Ensure "Sarah Johnson" does not exist (cleanup from previous runs)
python3 - <<'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
pwd = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, user, pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Ensure "Direct Sales" team exists
    team_ids = models.execute_kw(db, uid, pwd, 'crm.team', 'search', [[['name', '=', 'Direct Sales']]])
    if not team_ids:
        team_id = models.execute_kw(db, uid, pwd, 'crm.team', 'create', [{
            'name': 'Direct Sales',
            'use_opportunities': True,
            'use_leads': True
        }])
        print(f"Created 'Direct Sales' team with ID: {team_id}")
    else:
        print(f"'Direct Sales' team exists (ID: {team_ids[0]})")

    # 2. Cleanup User "Sarah Johnson" if exists
    # Find partners first
    partner_ids = models.execute_kw(db, uid, pwd, 'res.partner', 'search', [[['name', '=', 'Sarah Johnson']]])
    
    # Find users linked to these partners or with the login
    user_domain = ['|', ['login', '=', 'sarah.johnson@yourcompany.example.com'], ['name', '=', 'Sarah Johnson']]
    user_ids = models.execute_kw(db, uid, pwd, 'res.users', 'search', [user_domain])

    if user_ids:
        print(f"Cleaning up {len(user_ids)} existing users...")
        # We can't easily delete users in Odoo (referential integrity), so we archive them and rename login
        for u_id in user_ids:
            models.execute_kw(db, uid, pwd, 'res.users', 'write', [[u_id], {
                'active': False, 
                'login': f"archived_{u_id}_sarah",
                'name': f"Archived Sarah {u_id}"
            }])
        print("Users archived.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# Record initial user count for verification
INITIAL_USER_COUNT=$(odoo_db_query "SELECT COUNT(*) FROM res_users WHERE active = true;" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# Start Firefox and login
# We start at the CRM pipeline to force the agent to navigate to Settings
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="