#!/bin/bash
echo "=== Exporting Technician Availability Result ==="

source /workspace/scripts/task_utils.sh

# Record IDs for mapping
echo "Fetching User IDs..."
# We use SQL to get IDs to ensure we are tracking the right users
JOHN_ID=$(sdp_db_exec "SELECT user_id FROM aaauser WHERE first_name = 'John' AND last_name = 'Doe' LIMIT 1")
SARAH_ID=$(sdp_db_exec "SELECT user_id FROM aaauser WHERE first_name = 'Sarah' AND last_name = 'Smith' LIMIT 1")
ADMIN_ID=$(sdp_db_exec "SELECT user_id FROM aaauser WHERE first_name = 'Administrator' LIMIT 1")

echo "John ID: $JOHN_ID"
echo "Sarah ID: $SARAH_ID"

# Fetch Leave Data from DB
# Tables: TechUnavailability (tu), DateUnAvailability (dua), LeaveTypeDefinition (ltd)
# Join to get readable data
echo "Fetching Leave Data..."

# Note: SDP DB schema for leaves can vary slightly by version. 
# Standard path: TechUnavailability -> DateUnAvailability
# Timestamps in SDP are usually BigInt (milliseconds)

SQL_QUERY="
SELECT 
    tu.leaveid,
    tu.technicianid,
    tu.backuptechnicianid,
    ltd.name as leavetype,
    dua.leavedate,
    tu.createddate
FROM techunavailability tu
LEFT JOIN dateunavailability dua ON tu.leaveid = dua.leaveid
LEFT JOIN leavetypedefinition ltd ON tu.leavetypeid = ltd.leavetypeid
WHERE tu.technicianid = ${JOHN_ID:-0}
ORDER BY tu.createddate DESC;
"

LEAVE_DATA_CSV=$(sdp_db_exec "$SQL_QUERY" "servicedesk" | tr '|' ',')

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Python script to process CSV and create JSON
cat > /tmp/process_results.py << PYEOF
import json
import sys
import time

try:
    john_id = "${JOHN_ID}"
    sarah_id = "${SARAH_ID}"
    raw_csv = """${LEAVE_DATA_CSV}"""
    target_date_str = "$(cat /tmp/target_date_str.txt 2>/dev/null)"
    task_start_time = $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

    leaves = []
    if raw_csv.strip():
        rows = raw_csv.strip().split('\n')
        for row in rows:
            if not row.strip(): continue
            parts = row.split(',')
            if len(parts) >= 6:
                leaves.append({
                    "leave_id": parts[0],
                    "tech_id": parts[1],
                    "backup_tech_id": parts[2],
                    "leave_type": parts[3],
                    "leave_date_ms": int(parts[4]) if parts[4].isdigit() else 0,
                    "created_date_ms": int(parts[5]) if parts[5].isdigit() else 0
                })

    result = {
        "john_doe_id": john_id,
        "sarah_smith_id": sarah_id,
        "target_date_str": target_date_str,
        "task_start_time_sec": task_start_time,
        "leaves": leaves,
        "screenshot_path": "/tmp/task_final.png"
    }

    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))

PYEOF

python3 /tmp/process_results.py > "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="