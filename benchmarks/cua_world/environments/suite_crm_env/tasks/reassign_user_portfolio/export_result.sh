#!/bin/bash
echo "=== Exporting reassign_user_portfolio results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Fetch the current assigned_user_id for all injected records
suitecrm_db_query "SELECT id, assigned_user_id FROM accounts WHERE id LIKE 'acc_alex_%' OR id LIKE 'acc_taylor_%'" > /tmp/acc_assign.txt
suitecrm_db_query "SELECT id, assigned_user_id FROM opportunities WHERE id LIKE 'opp_alex_%' OR id LIKE 'opp_taylor_%'" > /tmp/opp_assign.txt

# Create JSON result using Python to safely construct the object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << 'EOF'
import json
import sys
import time

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

data = {
    "task_start": start_time,
    "task_end": int(time.time()),
    "accounts": {},
    "opportunities": {}
}

try:
    with open('/tmp/acc_assign.txt') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                data["accounts"][parts[0]] = parts[1]
                
    with open('/tmp/opp_assign.txt') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                data["opportunities"][parts[0]] = parts[1]
except Exception as e:
    data["error"] = str(e)

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
EOF "$TEMP_JSON"

# Safely copy to destination
rm -f /tmp/reassign_result.json 2>/dev/null || sudo rm -f /tmp/reassign_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/reassign_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/reassign_result.json
chmod 666 /tmp/reassign_result.json 2>/dev/null || sudo chmod 666 /tmp/reassign_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/reassign_result.json"
cat /tmp/reassign_result.json
echo "=== Export complete ==="