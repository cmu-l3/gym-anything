#!/bin/bash
echo "=== Exporting schedule_employee_activity result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_activity_count.txt 2>/dev/null || echo "0")

# Query Odoo for the latest activity for Marc Demo
# We export detailed JSON for the verifier
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoo_hr"
username = "admin"
password = "admin"
task_start_ts = int("$TASK_START")
initial_count = int("$INITIAL_COUNT")

result = {
    "task_start_ts": task_start_ts,
    "initial_count": initial_count,
    "final_count": 0,
    "new_activity_found": False,
    "activity_details": {},
    "error": None
}

try:
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Find Marc Demo
    emp_ids = models.execute_kw(db, uid, password, "hr.employee", "search",
                                [[["name", "=", "Marc Demo"]]])
    if not emp_ids:
        result["error"] = "Employee 'Marc Demo' not found"
    else:
        emp_id = emp_ids[0]
        
        # Search for activities for this employee
        # We fetch ALL to check counts, and sort by ID desc to get newest
        activity_ids = models.execute_kw(db, uid, password, "mail.activity", "search",
                                         [[["res_model", "=", "hr.employee"],
                                           ["res_id", "=", emp_id]]])
        
        result["final_count"] = len(activity_ids)
        
        if result["final_count"] > 0:
            # Get details of the most recently created activity (highest ID)
            # Note: search returns IDs, typically sorted, but let's be safe and read them
            # We filter for those created after task start if possible, or just grab the newest
            
            # Read details of all activities
            activities = models.execute_kw(db, uid, password, "mail.activity", "read",
                                           [activity_ids],
                                           {'fields': ['summary', 'date_deadline', 'activity_type_id', 
                                                       'note', 'create_date', 'create_uid']})
            
            # Sort by create_date (descending)
            activities.sort(key=lambda x: x['create_date'], reverse=True)
            
            latest = activities[0]
            
            # Convert Odoo datetime string to timestamp for comparison
            # Format usually: "YYYY-MM-DD HH:MM:SS"
            create_dt = datetime.datetime.strptime(latest['create_date'], "%Y-%m-%d %H:%M:%S")
            # Assume UTC for Odoo server time
            create_ts = create_dt.replace(tzinfo=datetime.timezone.utc).timestamp()
            
            # Check if this specific activity was created during the task
            # (Allowing a small buffer for clock skew, though docker usually syncs)
            created_during_task = create_ts >= (task_start_ts - 5)
            
            result["new_activity_found"] = True # We found *an* activity
            result["activity_details"] = {
                "id": latest["id"],
                "summary": latest.get("summary", ""),
                "date_deadline": latest.get("date_deadline", ""), # YYYY-MM-DD
                "note": latest.get("note", ""), # HTML content
                "activity_type": latest.get("activity_type_id", [0, "Unknown"])[1], # [id, name]
                "create_date": latest.get("create_date", ""),
                "created_during_task": created_during_task
            }

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export script finished. Result:")
print(json.dumps(result, indent=2))
PYTHON_EOF

# Ensure the result file is readable by the verifier (host user)
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="