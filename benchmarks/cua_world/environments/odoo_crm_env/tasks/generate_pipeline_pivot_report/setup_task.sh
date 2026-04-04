#!/bin/bash
set -e
echo "=== Setting up generate_pipeline_pivot_report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Install verification dependencies (pandas/openpyxl) inside container
#    This allows us to verify the Excel file structure during export
if ! python3 -c "import pandas" 2>/dev/null; then
    echo "Installing pandas for verification..."
    pip3 install pandas openpyxl --break-system-packages --quiet
fi

# 2. Setup Data (Users and Opportunities) via Python XML-RPC
#    We need a deterministic state for verification
python3 - <<PYEOF
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    if not uid:
        print("Authentication failed")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # --- Helper: Create User ---
    def create_user(name, login):
        # Check if exists
        existing = models.execute_kw(db, uid, password, 'res.users', 'search', [[['login', '=', login]]])
        if existing:
            return existing[0]
        # Create user
        user_id = models.execute_kw(db, uid, password, 'res.users', 'create', [{
            'name': name,
            'login': login,
            'password': login,
            'email': f'{login}@example.com',
            'groups_id': [(4, 1)] # Basic internal user
        }])
        return user_id

    # --- Helper: Get Stage ID ---
    def get_stage_id(name):
        stages = models.execute_kw(db, uid, password, 'crm.stage', 'search', [[['name', '=', name]]])
        return stages[0] if stages else False

    # --- Setup Users ---
    admin_id = uid
    alice_id = create_user("Alice Sales", "alice")
    print(f"User setup: Admin ID {admin_id}, Alice ID {alice_id}")

    # --- Setup Opportunities ---
    # First, archive/delete all existing leads to ensure clean numbers for pivot
    # (We assume this environment is transient for the task)
    all_leads = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[]])
    if all_leads:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [all_leads])
        print(f"Cleared {len(all_leads)} existing leads")

    # Create Seed Data
    leads_data = [
        # Admin Leads
        {'name': 'Big Software Deal', 'user_id': admin_id, 'stage_name': 'New', 'expected_revenue': 10000},
        {'name': 'Consulting Gig', 'user_id': admin_id, 'stage_name': 'Won', 'expected_revenue': 50000},
        
        # Alice Leads
        {'name': 'Retail Expansion', 'user_id': alice_id, 'stage_name': 'Qualified', 'expected_revenue': 25000},
        {'name': 'Local Ads', 'user_id': alice_id, 'stage_name': 'New', 'expected_revenue': 5000},
    ]

    for lead in leads_data:
        stage_id = get_stage_id(lead['stage_name'])
        vals = {
            'name': lead['name'],
            'user_id': lead['user_id'],
            'expected_revenue': lead['expected_revenue'],
            'type': 'opportunity'
        }
        if stage_id:
            vals['stage_id'] = stage_id
            
        new_id = models.execute_kw(db, uid, password, 'crm.lead', 'create', [vals])
        print(f"Created lead: {lead['name']} (ID {new_id})")

except Exception as e:
    print(f"Error seeding data: {e}")
    sys.exit(1)
PYEOF

# 3. Ensure Documents directory exists and is empty of previous reports
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/revenue_report.xlsx
chown ga:ga /home/ga/Documents

# 4. Prepare Browser
ensure_odoo_logged_in "http://localhost:8069/web"

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="