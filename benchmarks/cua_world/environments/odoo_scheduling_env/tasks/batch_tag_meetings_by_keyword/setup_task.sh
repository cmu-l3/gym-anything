#!/bin/bash
set -e
echo "=== Setting up batch_tag_meetings_by_keyword task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Odoo is running and accessible
ensure_odoo_logged_in

# PRE-CLEANUP: Remove the "Audit" tag from any existing events and delete the tag definition
# This ensures the agent must create/apply it fresh.
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Find the "Audit" tag
    tags = models.execute_kw(db, uid, 'admin', 'calendar.event.type', 'search',
                             [[['name', '=', 'Audit']]])
    
    if tags:
        tag_id = tags[0]
        print(f"Found existing 'Audit' tag (id={tag_id}). Cleaning up...")
        
        # 2. Find events using this tag
        events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                   [[['categ_ids', 'in', [tag_id]]]])
        
        if events:
            # Remove tag from these events
            # We read the events to preserve other tags, but for simplicity in this setup, 
            # we'll just unlink the tag which automatically removes the relation.
            print(f"Removing tag from {len(events)} events...")
        
        # 3. Delete the tag
        models.execute_kw(db, uid, 'admin', 'calendar.event.type', 'unlink', [[tag_id]])
        print("Deleted 'Audit' tag.")
    else:
        print("'Audit' tag does not exist. Clean slate.")

except Exception as e:
    print(f"Error during cleanup: {e}", file=sys.stderr)
PYTHON_EOF

# Launch Firefox to the Calendar view
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="