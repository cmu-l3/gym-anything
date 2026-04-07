#!/bin/bash
echo "=== Exporting process_employee_promotion result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Odoo database for the final state of Ernest Reed's record
# We export this to a JSON file that the verifier will read
python3 << 'PYEOF'
import xmlrpc.client, json, sys, re
from datetime import datetime

url = "http://localhost:8069"
db = "odoo_hr"
output_file = "/tmp/task_result.json"

result = {
    "employee_found": False,
    "fields": {},
    "timestamp_valid": False,
    "task_start": 0,
    "write_date_ts": 0
}

try:
    # Get task start time
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            task_start = int(f.read().strip())
    except:
        task_start = 0
    result["task_start"] = task_start

    # Connect to Odoo
    common = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common")
    uid = common.authenticate(db, "admin", "admin", {})
    models = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object")

    # Search for Ernest Reed
    emp_ids = models.execute_kw(db, uid, "admin", "hr.employee", "search",
                            [[["name", "=", "Ernest Reed"]]])
    
    if emp_ids:
        result["employee_found"] = True
        
        # Read fields
        fields = ["job_title", "department_id", "job_id", "parent_id", "coach_id",
                  "work_phone", "work_email", "write_date"]
        data = models.execute_kw(db, uid, "admin", "hr.employee", "read",
                               [emp_ids[:1]], {"fields": fields})[0]
        
        # Normalize data structure for JSON export
        # Many2one fields return [id, "Name"] or False
        result["fields"] = {
            "job_title": data.get("job_title") or "",
            "work_phone": data.get("work_phone") or "",
            "work_email": data.get("work_email") or "",
            "department_name": data.get("department_id")[1] if data.get("department_id") else "",
            "job_position_name": data.get("job_id")[1] if data.get("job_id") else "",
            "manager_name": data.get("parent_id")[1] if data.get("parent_id") else "",
            "coach_name": data.get("coach_id")[1] if data.get("coach_id") else ""
        }
        
        # Check write_date for anti-gaming
        write_date_str = data.get("write_date", "")
        if write_date_str:
            # Odoo returns UTC strings like "2023-10-27 10:00:00"
            write_dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
            write_ts = int(write_dt.timestamp())
            result["write_date_ts"] = write_ts
            # Allow a small buffer for clock skew if needed, but usually docker time is synced
            if write_ts >= task_start:
                result["timestamp_valid"] = True
                
except Exception as e:
    result["error"] = str(e)

# Save result
with open(output_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {output_file}")
PYEOF

# Set permissions so the ga user (and verifier) can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Also include screenshot info in a way verifier can check if needed
if [ -f /tmp/task_final.png ]; then
    echo "Screenshot captured successfully"
fi

echo "=== Export complete ==="