#!/bin/bash
set -e
echo "=== Setting up task: Structure Unformatted Leads ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Seed the malformed leads using Python/XML-RPC
# We use a unique reference in the description to track them later, 
# even if the agent changes the name.
echo "Seeding malformed leads..."
python3 << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
passwd = "admin"

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, user, passwd, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# Leads to create
leads = [
    {
        "name": "Alice Wong - Q3 Software License",
        "contact_name": False, # Empty initially
        "priority": "0",
        "description": "REF_LEAD_001", # Unique ID for verification
        "type": "opportunity"
    },
    {
        "name": "David Miller - Fleet Audit",
        "contact_name": False,
        "priority": "0",
        "description": "REF_LEAD_002",
        "type": "opportunity"
    },
    {
        "name": "URGENT: Elena Sisko - Security Breach Response",
        "contact_name": False,
        "priority": "1", # Starts as Medium/Low, needs to be Very High
        "description": "REF_LEAD_003",
        "type": "opportunity"
    }
]

# Clean up any previous runs (search by ref_id in description)
for lead in leads:
    ref = lead['description']
    existing = models.execute_kw(db, uid, passwd, 'crm.lead', 'search', [[['description', 'ilike', ref]]])
    if existing:
        models.execute_kw(db, uid, passwd, 'crm.lead', 'unlink', [existing])
        print(f"Cleaned up existing lead with ref {ref}")

# Create new leads
for lead in leads:
    cid = models.execute_kw(db, uid, passwd, 'crm.lead', 'create', [lead])
    print(f"Created lead: {lead['name']} (ID: {cid})")

PYEOF

# Ensure Firefox is open and navigated to the CRM pipeline
# Action 209 is CRM Pipeline, View 139 is Kanban
ensure_odoo_logged_in "http://localhost:8069/web#action=209&model=crm.lead&view_type=kanban&cids=1&menu_id=139"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="