#!/bin/bash
echo "=== Setting up weekly_ops_review_setup task ==="

source /workspace/scripts/task_utils.sh

# Remove any pre-existing 'Operations Weekly Review' events so the slate is clean
python3 << 'PYTHON_EOF'
import xmlrpc.client, sys
url = 'http://localhost:8069'
db = 'odoo_scheduling'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    existing = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search',
                                 [[['name', 'ilike', 'Operations Weekly Review']]])
    if existing:
        models.execute_kw(db, uid, 'admin', 'calendar.event', 'unlink', [existing])
        print(f"Removed {len(existing)} existing 'Operations Weekly Review' event(s)")
    else:
        print("No pre-existing 'Operations Weekly Review' events found — clean slate")
except Exception as e:
    print(f"Warning: {e}", file=sys.stderr)
PYTHON_EOF

# Record baseline AFTER cleanup so event count reflects clean starting state (Anti-pattern 3)
record_task_baseline "weekly_ops_review_setup"

# Navigate Firefox to the Odoo Calendar so the agent starts in the right place
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
navigate_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"
sleep 3

take_screenshot /tmp/weekly_ops_review_start.png

echo "Task start state: Odoo Calendar is open."
echo "Agent must create a recurring weekly 'Operations Weekly Review' meeting with senior leadership and an email reminder."
echo "=== weekly_ops_review_setup task setup complete ==="
