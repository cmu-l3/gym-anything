#!/bin/bash
set -e
echo "=== Setting up add_meeting_attendees task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset the event to a known clean state (Original 3 attendees only)
#    and Record Baseline (ID, create_date) for anti-gaming.
python3 << 'PYEOF'
import xmlrpc.client, json, sys, time

url = "http://localhost:8069"
db = "odoo_scheduling"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # 1. Find the event
    events = models.execute_kw(db, uid, password, "calendar.event", "search_read",
        [[["name", "=", "Product Roadmap Planning"]]],
        {"fields": ["id", "name", "partner_ids"], "limit": 1})

    event_id = None
    if not events:
        print("Event not found, creating it...")
        # Create if missing (fallback)
        # Need partner IDs first
        p_names = ["Alice Johnson", "David Chen", "Emma Thompson"]
        p_ids = []
        for name in p_names:
            p = models.execute_kw(db, uid, password, "res.partner", "search", [[["name", "=", name]]])
            if p: p_ids.append(p[0])
        
        event_id = models.execute_kw(db, uid, password, "calendar.event", "create", [{
            "name": "Product Roadmap Planning",
            "start": "2026-03-16 09:00:00", # Arbitrary future date for fallback
            "stop": "2026-03-16 11:00:00",
            "partner_ids": [[6, 0, p_ids]]
        }])
    else:
        event_id = events[0]["id"]
        # Reset attendees to just the original 3
        p_names = ["Alice Johnson", "David Chen", "Emma Thompson"]
        p_ids = []
        for name in p_names:
            p = models.execute_kw(db, uid, password, "res.partner", "search", [[["name", "=", name]]])
            if p: p_ids.append(p[0])
        
        models.execute_kw(db, uid, password, "calendar.event", "write", 
            [[event_id], {"partner_ids": [[6, 0, p_ids]]}])
        print(f"Reset attendees for event {event_id}")

    # 2. Get final baseline state
    baseline_event = models.execute_kw(db, uid, password, "calendar.event", "read",
        [event_id], {"fields": ["id", "create_date", "name"]})[0]

    baseline_data = {
        "event_id": baseline_event["id"],
        "create_date": baseline_event["create_date"],
        "name": baseline_event["name"]
    }

    with open("/tmp/task_baseline.json", "w") as f:
        json.dump(baseline_data, f)
    print("Baseline saved.")

except Exception as e:
    print(f"Setup Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

# 2. Launch Firefox and navigate to Calendar
# Use Week view to make it easier to find the meeting
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event&view_type=week"

# 3. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="