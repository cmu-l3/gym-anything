#!/bin/bash
echo "=== Exporting optimize_meeting_schedule result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export the state of the two specific events to JSON
python3 << 'PYTHON_EOF'
import xmlrpc.client
import json
import sys
import datetime

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

output = {
    "team_standup": None,
    "financial_review": None,
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Fetch Team Standup
    standup_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Team Standup']]])
    if standup_ids:
        # Get the one with the latest ID if duplicates exist (though setup cleaned them)
        standup = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [[max(standup_ids)], ['name', 'start', 'stop', 'duration', 'location']])
        output["team_standup"] = standup[0]

    # Fetch Q2 Financial Review
    review_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search',
        [[['name', '=', 'Q2 Financial Review']]])
    if review_ids:
        review = models.execute_kw(db, uid, password, 'calendar.event', 'read',
            [[max(review_ids)], ['name', 'start', 'stop', 'duration', 'location']])
        output["financial_review"] = review[0]

except Exception as e:
    output["error"] = str(e)

# Write to file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
PYTHON_EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="