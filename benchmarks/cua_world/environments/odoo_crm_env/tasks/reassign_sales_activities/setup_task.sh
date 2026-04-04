#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Reassign Sales Activities ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Create Users and Activities via XML-RPC
# We use a Python script to interact with Odoo's API to ensure clean data setup
python3 - <<'PYEOF'
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
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Create Users
    def create_user(name, login):
        existing = models.execute_kw(db, uid, passwd, 'res.users', 'search', [[['login', '=', login]]])
        if existing:
            return existing[0]
        user_id = models.execute_kw(db, uid, passwd, 'res.users', 'create', [{
            'name': name,
            'login': login,
            'email': f'{login}@example.com',
            'active': True
        }])
        return user_id

    ellis_id = create_user("Ellis Absent", "ellis")
    sam_id = create_user("Sam Cover", "sam")
    print(f"Users setup: Ellis ({ellis_id}), Sam ({sam_id})")

    # 2. Cleanup existing activities for these users (idempotency)
    # This prevents duplicate activities if setup runs multiple times
    existing_activities = models.execute_kw(db, uid, passwd, 'mail.activity', 'search',
        [[['user_id', 'in', [ellis_id, sam_id]]]])
    if existing_activities:
        models.execute_kw(db, uid, passwd, 'mail.activity', 'unlink', [existing_activities])
        print("Cleaned up existing activities")

    # 3. Create Opportunities
    opps_data = [
        {"name": "Global Logistics Expansion", "partner": "Global Logistics Inc", "revenue": 50000},
        {"name": "TechFlow Server Upgrade", "partner": "TechFlow Systems", "revenue": 12000},
        {"name": "EcoGreen Solar Install", "partner": "EcoGreen Solutions", "revenue": 28000}
    ]

    opp_ids = []
    for opp in opps_data:
        # Check if partner exists or create
        existing_partner = models.execute_kw(db, uid, passwd, 'res.partner', 'search', [[['name', '=', opp['partner']]]])
        if existing_partner:
            partner_id = existing_partner[0]
        else:
            partner_id = models.execute_kw(db, uid, passwd, 'res.partner', 'create', [{'name': opp['partner']}])
        
        # Check if opp exists or create
        existing_opp = models.execute_kw(db, uid, passwd, 'crm.lead', 'search', [[['name', '=', opp['name']]]])
        if existing_opp:
            opp_id = existing_opp[0]
            # Ensure it's assigned to Ellis for context (though not strictly required for the task)
            models.execute_kw(db, uid, passwd, 'crm.lead', 'write', [opp_id, {'user_id': ellis_id}])
        else:
            opp_id = models.execute_kw(db, uid, passwd, 'crm.lead', 'create', [{
                'name': opp['name'],
                'partner_id': partner_id,
                'expected_revenue': opp['revenue'],
                'type': 'opportunity',
                'user_id': ellis_id
            }])
        opp_ids.append(opp_id)

    # 4. Create Activities linked to these opportunities, assigned to Ellis
    # Activity Types: Search for Call/Email/ToDo
    def get_activity_type(name):
        res = models.execute_kw(db, uid, passwd, 'mail.activity.type', 'search', [[['name', 'ilike', name]]])
        return res[0] if res else 1

    type_call = get_activity_type("Call")
    type_email = get_activity_type("Email")
    type_todo = get_activity_type("To Do")

    activities = [
        {
            "res_id": opp_ids[0], 
            "res_model": "crm.lead", 
            "activity_type_id": type_call, 
            "summary": "Contract Negotiation", 
            "user_id": ellis_id,
            "note": "Urgent discussion about payment terms.",
            "date_deadline": time.strftime("%Y-%m-%d") # Due today
        },
        {
            "res_id": opp_ids[1], 
            "res_model": "crm.lead", 
            "activity_type_id": type_email, 
            "summary": "Pricing Update", 
            "user_id": ellis_id,
            "note": "Send the updated Q3 price list.",
            "date_deadline": time.strftime("%Y-%m-%d")
        },
        {
            "res_id": opp_ids[2], 
            "res_model": "crm.lead", 
            "activity_type_id": type_todo, 
            "summary": "Prepare Demo", 
            "user_id": ellis_id,
            "note": "Setup the solar panel demo kit.",
            "date_deadline": time.strftime("%Y-%m-%d")
        }
    ]

    created_ids = []
    for act in activities:
        aid = models.execute_kw(db, uid, passwd, 'mail.activity', 'create', [act])
        created_ids.append(aid)

    print(f"Created activities: {created_ids}")

    # Save IDs to file for verification logic
    with open('/tmp/initial_activity_ids.txt', 'w') as f:
        f.write(','.join(map(str, created_ids)))
    
    with open('/tmp/user_ids.txt', 'w') as f:
        f.write(f"{ellis_id},{sam_id}")

except Exception as e:
    print(f"Setup failed: {e}")
    sys.exit(1)
PYEOF

# Ensure Firefox is running and logged in
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&menu_id=139"

# Focus Firefox and maximize
if pgrep -f firefox > /dev/null; then
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="