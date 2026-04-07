#!/bin/bash
set -e
echo "=== Setting up create_saved_calendar_filter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any pre-existing filter with this name to ensure a clean state
echo "Cleaning up existing filters..."
python3 << PYTHON_EOF
import xmlrpc.client
import sys

url = '$ODOO_URL'
db = '$ODOO_DB'
username = '$ODOO_USER'
password = '$ODOO_PASSWORD'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Find existing filters named 'CFO Schedule' for calendar
    existing_ids = models.execute_kw(db, uid, password, 'ir.filters', 'search',
        [[['name', '=', 'CFO Schedule'], ['model_id', '=', 'calendar.event']]])
        
    if existing_ids:
        print(f"Removing {len(existing_ids)} pre-existing filters...")
        models.execute_kw(db, uid, password, 'ir.filters', 'unlink', [existing_ids])
    else:
        print("No existing filters found.")
        
except Exception as e:
    print(f"Setup warning: {e}", file=sys.stderr)
PYTHON_EOF

# Ensure Firefox is running and logged in, navigating to Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="