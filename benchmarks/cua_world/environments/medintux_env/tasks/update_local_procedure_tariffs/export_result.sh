#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Run Verification Logic INSIDE the container
# We use Python here to query the DB and verify state, then dump to JSON
cat > /tmp/internal_verify.py << 'PYEOF'
import pymysql
import json
import os
import sys

result = {
    "db_connection": False,
    "updates_correct": False,
    "integrity_maintained": False,
    "log_file_exists": False,
    "log_file_size": 0,
    "updated_codes": {},
    "control_codes": {},
    "errors": []
}

try:
    # Check 1: Log file
    log_path = "/home/ga/Documents/update_log.txt"
    if os.path.exists(log_path):
        result["log_file_exists"] = True
        result["log_file_size"] = os.path.getsize(log_path)
    
    # Check 2: Database State
    conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest')
    cursor = conn.cursor()
    result["db_connection"] = True
    
    # Verify Target Updates
    targets = {
        'CS': 30.00,
        'APC': 55.00,
        'TC': 25.00,
        'K': 20.00,
        'IMP': 25.50
    }
    
    correct_updates = 0
    for code, expected in targets.items():
        cursor.execute(f"SELECT Tarif FROM CCAM_Local_Tarifs WHERE Code='{code}'")
        row = cursor.fetchone()
        if row:
            actual = float(row[0])
            result["updated_codes"][code] = actual
            if abs(actual - expected) < 0.01:
                correct_updates += 1
            else:
                result["errors"].append(f"Code {code}: expected {expected}, got {actual}")
        else:
            result["errors"].append(f"Code {code} not found")
            
    if correct_updates == len(targets):
        result["updates_correct"] = True
        
    # Verify Integrity (Controls)
    controls = {
        'C': 25.00,
        'V': 33.00,
        'COE': 46.00
    }
    
    correct_controls = 0
    for code, expected in controls.items():
        cursor.execute(f"SELECT Tarif FROM CCAM_Local_Tarifs WHERE Code='{code}'")
        row = cursor.fetchone()
        if row:
            actual = float(row[0])
            result["control_codes"][code] = actual
            if abs(actual - expected) < 0.01:
                correct_controls += 1
            else:
                result["errors"].append(f"INTEGRITY ERROR: Control code {code} changed! Expected {expected}, got {actual}")
        else:
            result["errors"].append(f"Control code {code} missing")
            
    if correct_controls == len(controls):
        result["integrity_maintained"] = True
        
    conn.close()

except Exception as e:
    result["errors"].append(str(e))

# Output JSON
print(json.dumps(result))
PYEOF

# Run the verification script and save to /tmp/task_result.json
python3 /tmp/internal_verify.py > /tmp/task_result.json 2>/dev/null

# Add screenshot existence to result
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Merge timestamp info using jq if available, or simple python script
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_exists'] = $SCREENSHOT_EXISTS
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="