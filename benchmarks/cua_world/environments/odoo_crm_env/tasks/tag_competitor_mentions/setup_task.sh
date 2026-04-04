#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Tag Competitor Mentions ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Python script to seed data
python3 << 'PYEOF'
import xmlrpc.client
import sys

url = "http://localhost:8069"
db = "odoodb"
user = "admin"
password = "admin"

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, user, password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# 1. Cleanup: Remove tag if it exists (idempotency)
tag_ids = models.execute_kw(db, uid, password, 'crm.tag', 'search', [[['name', '=', 'Competitor: OmniTech']]])
if tag_ids:
    models.execute_kw(db, uid, password, 'crm.tag', 'unlink', [tag_ids])
    print("Cleaned up existing target tag.")

# 2. Cleanup: Remove specific leads to avoid duplicates from previous runs
lead_names = [
    "Office Expansion - KwikE Mart", 
    "Server Upgrade - CyberDyne Systems", 
    "Fleet Management - Planet Express", 
    "Consulting Services - Wayne Enterprises", 
    "Software License - Stark Industries"
]
existing_leads = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', 'in', lead_names]]])
if existing_leads:
    models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [existing_leads])
    print(f"Cleaned up {len(existing_leads)} existing leads.")

# 3. Create Leads
# Data: Name, Partner, Description (Internal Notes), Revenue, Should match?
leads_data = [
    {
        "name": "Office Expansion - KwikE Mart", 
        "partner": "KwikE Mart",
        "desc": "Client is looking for 50 desks. Budget is tight. Decision by next week.",
        "rev": 12000
    },
    {
        "name": "Server Upgrade - CyberDyne Systems", 
        "partner": "CyberDyne Systems",
        "desc": "Current provider is OmniTech, but they are unhappy with the support response time. Good opportunity to displace.",
        "rev": 45000
    },
    {
        "name": "Fleet Management - Planet Express", 
        "partner": "Planet Express",
        "desc": "Meeting went well. They are interested in the tracking module. Send proposal by Friday.",
        "rev": 28000
    },
    {
        "name": "Consulting Services - Wayne Enterprises", 
        "partner": "Wayne Enterprises",
        "desc": "Competitor Analysis: OmniTech has offered a lower hourly rate ($150/hr). We need to justify our value proposition.",
        "rev": 15000
    },
    {
        "name": "Software License - Stark Industries", 
        "partner": "Stark Industries",
        "desc": "They are reviewing the contract. Legal team is involved. Also looking at SAP and Oracle options.",
        "rev": 85000
    }
]

for lead in leads_data:
    # Create or get partner
    p_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', lead['partner']]]])
    if p_ids:
        pid = p_ids[0]
    else:
        pid = models.execute_kw(db, uid, password, 'res.partner', 'create', [{'name': lead['partner']}])

    # Create lead
    models.execute_kw(db, uid, password, 'crm.lead', 'create', [{
        'name': lead['name'],
        'partner_id': pid,
        'description': lead['desc'],
        'expected_revenue': lead['rev'],
        'type': 'opportunity'
    }])
    print(f"Created lead: {lead['name']}")

PYEOF

# Ensure Firefox is open and logged in
ensure_odoo_logged_in

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="