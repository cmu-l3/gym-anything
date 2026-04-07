#!/bin/bash
set -e
echo "=== Setting up Merge Related Events Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset Database State via Python/XML-RPC
# We ensure the two original events exist and the target merged event does NOT exist.
python3 << 'PYTHON_EOF'
import xmlrpc.client
import datetime
import sys

url = 'http://localhost:8069'
db = 'odoo_scheduling'
username = 'admin'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Helper to find partner IDs
    def get_partner_id(name):
        ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', name]]])
        return ids[0] if ids else None

    # 1. Clean up: Delete the target event if it exists from a previous run
    target_name = "Product & Engineering Joint Review"
    existing_targets = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', '=', target_name]]])
    if existing_targets:
        models.execute_kw(db, uid, password, 'calendar.event', 'unlink', [existing_targets])
        print(f"Cleaned up existing target event: {target_name}")

    # 2. Ensure Original Event 1: "Product Strategy Review"
    # Attendees: Alice Johnson, Emma Thompson, David Chen
    evt1_name = "Product Strategy Review"
    p_alice = get_partner_id("Alice Johnson")
    p_emma = get_partner_id("Emma Thompson")
    p_david = get_partner_id("David Chen")
    
    # Calculate date: 2 days from now (fixed anchor for consistency)
    now = datetime.datetime.now()
    start_dt = (now + datetime.timedelta(days=2)).replace(hour=10, minute=0, second=0)
    stop_dt = start_dt + datetime.timedelta(hours=1.5)
    
    # Check if exists, if not create
    evt1_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', '=', evt1_name]]])
    if not evt1_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
            'name': evt1_name,
            'start': start_dt.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': stop_dt.strftime('%Y-%m-%d %H:%M:%S'),
            'location': 'Product Lab',
            'partner_ids': [[6, 0, [p_alice, p_emma, p_david]]],
            'description': 'Review product roadmap.'
        }])
        print(f"Created event: {evt1_name}")
    else:
        # Ensure attendees are correct
        models.execute_kw(db, uid, password, 'calendar.event', 'write', [evt1_ids, {
            'partner_ids': [[6, 0, [p_alice, p_emma, p_david]]],
            'start': start_dt.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': stop_dt.strftime('%Y-%m-%d %H:%M:%S')
        }])
        print(f"Reset event: {evt1_name}")

    # 3. Ensure Original Event 2: "Engineering Architecture Discussion"
    # Attendees: David Chen, Emma Thompson, Luis Fernandez
    evt2_name = "Engineering Architecture Discussion"
    p_luis = get_partner_id("Luis Fernandez")
    
    # Date: Same day as Event 1 but different time (or next day, doesn't matter much as long as they exist)
    # Let's put it on the same day for maximum "merge" logic incentive
    start_dt2 = (now + datetime.timedelta(days=2)).replace(hour=14, minute=0, second=0)
    stop_dt2 = start_dt2 + datetime.timedelta(hours=2)
    
    evt2_ids = models.execute_kw(db, uid, password, 'calendar.event', 'search', [[['name', '=', evt2_name]]])
    if not evt2_ids:
        models.execute_kw(db, uid, password, 'calendar.event', 'create', [{
            'name': evt2_name,
            'start': start_dt2.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': stop_dt2.strftime('%Y-%m-%d %H:%M:%S'),
            'location': 'Engineering Lab',
            'partner_ids': [[6, 0, [p_david, p_emma, p_luis]]],
            'description': 'Architecture review.'
        }])
        print(f"Created event: {evt2_name}")
    else:
        models.execute_kw(db, uid, password, 'calendar.event', 'write', [evt2_ids, {
            'partner_ids': [[6, 0, [p_david, p_emma, p_luis]]],
            'start': start_dt2.strftime('%Y-%m-%d %H:%M:%S'),
            'stop': stop_dt2.strftime('%Y-%m-%d %H:%M:%S')
        }])
        print(f"Reset event: {evt2_name}")

except Exception as e:
    print(f"Setup Error: {e}")
    sys.exit(1)
PYTHON_EOF

# 2. Launch Firefox and navigate to Calendar
echo "Launching Firefox..."
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="