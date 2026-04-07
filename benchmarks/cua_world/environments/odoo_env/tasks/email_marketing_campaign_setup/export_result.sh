#!/bin/bash
# Export script for email_marketing_campaign_setup
# Queries Odoo for mailing lists, contacts, and mailing campaigns

echo "=== Exporting Email Marketing Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to query Odoo and export JSON
python3 << 'PYEOF'
import xmlrpc.client
import json
import sys
import datetime

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'
TASK_START = int(sys.argv[1]) if len(sys.argv) > 1 else 0

output = {
    "list_found": False,
    "contacts_count": 0,
    "correct_emails_found": [],
    "mailing_found": False,
    "mailing_details": {},
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
    uid = common.authenticate(DB, USERNAME, PASSWORD, {})
    models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')

    # 1. Check Mailing List
    target_list_name = "Eco-Conscious Interest Group"
    lists = models.execute_kw(DB, uid, PASSWORD, 'mailing.list', 'search_read',
        [[['name', '=', target_list_name]]],
        {'fields': ['id', 'name', 'contact_count']})
    
    list_id = None
    if lists:
        output["list_found"] = True
        list_data = lists[0]
        list_id = list_data['id']
        output["list_details"] = list_data
        
        # 2. Check Contacts in this list
        # In Odoo, mailing.contact has a Many2many relationship 'list_ids' with mailing.list
        # We search for contacts that belong to this list ID
        contacts = models.execute_kw(DB, uid, PASSWORD, 'mailing.contact', 'search_read',
            [[['list_ids', 'in', [list_id]]]],
            {'fields': ['email']})
        
        output["contacts_count"] = len(contacts)
        found_emails = [c['email'] for c in contacts]
        
        expected_emails = [
            "sarah.green@example.org",
            "driver@naturemail.net",
            "purchasing@ecosupplies.test"
        ]
        
        output["correct_emails_found"] = [e for e in expected_emails if e in found_emails]

    # 3. Check Mailing Campaign
    # We look for a mailing created recently that targets our list
    # Criteria: Subject matches partial, state is scheduled/in_queue
    
    domain = [
        ['subject', 'ilike', 'Bamboo'],
        ['create_date', '>=', datetime.datetime.fromtimestamp(TASK_START).strftime('%Y-%m-%d %H:%M:%S')]
    ]
    
    mailings = models.execute_kw(DB, uid, PASSWORD, 'mailing.mailing', 'search_read',
        [domain],
        {'fields': ['id', 'subject', 'body_html', 'body_arch', 'state', 'schedule_date', 'contact_list_ids']})
    
    if mailings:
        # Get the most recent one matching criteria
        mailing = mailings[-1] # List is usually ordered by ID default, so last is newest
        
        # Check if it targets the correct list
        targets_correct_list = False
        if list_id and 'contact_list_ids' in mailing:
            if list_id in mailing['contact_list_ids']:
                targets_correct_list = True
                
        output["mailing_found"] = True
        output["mailing_details"] = {
            "subject": mailing.get('subject'),
            "state": mailing.get('state'), # should be 'schedule' (Scheduled) or 'in_queue'
            "schedule_date": mailing.get('schedule_date'),
            "targets_correct_list": targets_correct_list,
            "body_content": mailing.get('body_html') or mailing.get('body_arch') or ""
        }

except Exception as e:
    output["error"] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="