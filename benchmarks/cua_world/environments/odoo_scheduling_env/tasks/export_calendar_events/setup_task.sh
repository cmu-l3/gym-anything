#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up export_calendar_events task ==="

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/calendar_export.csv
rm -f /home/ga/Downloads/calendar*.csv 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/Downloads/calendar*.csv 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Record Ground Truth (List of event names currently in DB)
# We use this to verify the exported CSV actually contains real data
python3 << 'PYEOF'
import xmlrpc.client, sys, json
try:
    url = 'http://localhost:8069'
    db = 'odoo_scheduling'
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
    
    # Fetch all event names
    events = models.execute_kw(db, uid, 'admin', 'calendar.event', 'search_read',
                               [[]], {'fields': ['name']})
    names = [e['name'] for e in events]
    
    with open('/tmp/ground_truth_events.json', 'w') as f:
        json.dump(names, f)
        
    print(f"Recorded {len(names)} events for ground truth.")
except Exception as e:
    print(f"Error recording ground truth: {e}", file=sys.stderr)
    # Write empty list as fallback
    with open('/tmp/ground_truth_events.json', 'w') as f:
        f.write("[]")
PYEOF

# 4. Launch Application (Firefox -> Odoo Calendar)
# We start in Calendar view, forcing the agent to switch to List view
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=calendar"

# 5. Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="