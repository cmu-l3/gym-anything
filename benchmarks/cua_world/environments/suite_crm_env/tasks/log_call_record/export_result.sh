#!/bin/bash
echo "=== Exporting log_call_record results ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final_state.png

# Create a robust Python script to extract DB data safely (handles newlines in descriptions)
cat > /tmp/export_db_state.py << 'EOF'
import subprocess
import json
import os

def db_query(sql):
    try:
        return subprocess.check_output(
            ["docker", "exec", "suitecrm-db", "mysql", "-u", "suitecrm", "-psuitecrm_pass", "suitecrm", "-N", "-e", sql],
            text=True
        ).strip()
    except Exception as e:
        return ""

result = {
    "call_found": False,
    "task_start_time": 0,
    "initial_call_count": 0,
    "current_call_count": 0,
    "screenshot_path": "/tmp/task_final_state.png"
}

# Fetch timestamps and counts
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start_time'] = int(f.read().strip())
except Exception:
    pass

try:
    with open('/tmp/initial_call_count.txt', 'r') as f:
        result['initial_call_count'] = int(f.read().strip())
except Exception:
    pass

count_str = db_query("SELECT COUNT(*) FROM calls WHERE deleted=0")
result['current_call_count'] = int(count_str) if count_str.isdigit() else 0

# Retrieve the specific target call by subject match
call_id = db_query("SELECT id FROM calls WHERE name LIKE '%Invoice #4821%' AND deleted=0 ORDER BY date_entered DESC LIMIT 1")

if call_id:
    result['call_found'] = True
    result['call_id'] = call_id
    result['name'] = db_query(f"SELECT name FROM calls WHERE id='{call_id}'")
    result['status'] = db_query(f"SELECT status FROM calls WHERE id='{call_id}'")
    result['direction'] = db_query(f"SELECT direction FROM calls WHERE id='{call_id}'")
    result['duration_hours'] = db_query(f"SELECT duration_hours FROM calls WHERE id='{call_id}'")
    result['duration_minutes'] = db_query(f"SELECT duration_minutes FROM calls WHERE id='{call_id}'")
    result['description'] = db_query(f"SELECT description FROM calls WHERE id='{call_id}'")
    result['parent_type'] = db_query(f"SELECT parent_type FROM calls WHERE id='{call_id}'")
    result['parent_id'] = db_query(f"SELECT parent_id FROM calls WHERE id='{call_id}'")
    
    ts_str = db_query(f"SELECT UNIX_TIMESTAMP(date_entered) FROM calls WHERE id='{call_id}'")
    result['date_entered_ts'] = int(ts_str) if ts_str.isdigit() else 0

    # Resolve related contact/account name from parent_id
    result['parent_name'] = ""
    ptype = result['parent_type']
    pid = result['parent_id']
    if ptype == 'Contacts' and pid:
        result['parent_name'] = db_query(f"SELECT last_name FROM contacts WHERE id='{pid}'")
    elif ptype == 'Accounts' and pid:
        result['parent_name'] = db_query(f"SELECT name FROM accounts WHERE id='{pid}'")

    # Check join table for invitees (calls_contacts)
    result['invitee_last_name'] = db_query(f"SELECT c.last_name FROM calls_contacts cc JOIN contacts c ON cc.contact_id=c.id WHERE cc.call_id='{call_id}' AND cc.deleted=0 AND c.deleted=0 LIMIT 1")

# Write results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Run the extraction
python3 /tmp/export_db_state.py
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== log_call_record export complete ==="