#!/bin/bash
echo "=== Exporting add_meeting_attendees result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to query current state and compare with baseline
python3 << 'PYEOF'
import xmlrpc.client, json, sys, os

url = "http://localhost:8069"
db = "odoo_scheduling"
password = "admin"

result = {
    "task_start": 0,
    "task_end": 0,
    "baseline_event_id": None,
    "baseline_create_date": None,
    "final_event_found": False,
    "final_event_id": None,
    "final_create_date": None,
    "attendee_names": [],
    "attendee_ids": [],
    "error": None
}

try:
    # Load baseline
    if os.path.exists("/tmp/task_baseline.json"):
        with open("/tmp/task_baseline.json", "r") as f:
            baseline = json.load(f)
            result["baseline_event_id"] = baseline.get("event_id")
            result["baseline_create_date"] = baseline.get("create_date")

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Search for the event by name
    # We search for ALL events with this name to detect duplicates
    events = models.execute_kw(db, uid, password, "calendar.event", "search_read",
        [[["name", "=", "Product Roadmap Planning"]]],
        {"fields": ["id", "name", "create_date", "partner_ids"]})

    if events:
        # If multiple exist, try to find the one matching baseline ID
        target_event = None
        for evt in events:
            if evt["id"] == result["baseline_event_id"]:
                target_event = evt
                break
        
        # If not found by ID (deleted?), just take the first one found (recreated)
        if not target_event:
            target_event = events[0]
        
        result["final_event_found"] = True
        result["final_event_id"] = target_event["id"]
        result["final_create_date"] = target_event["create_date"]
        result["attendee_ids"] = target_event["partner_ids"]

        # Resolve partner names
        if target_event["partner_ids"]:
            partners = models.execute_kw(db, uid, password, "res.partner", "search_read",
                [[["id", "in", target_event["partner_ids"]]]],
                {"fields": ["name"]})
            result["attendee_names"] = [p["name"] for p in partners]

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Fix permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="