#!/bin/bash
echo "=== Exporting Detect Ephemeral Account Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch local_rules.xml content for static analysis
echo "Fetching local_rules.xml..."
docker cp wazuh-wazuh.manager-1:/var/ossec/etc/rules/local_rules.xml /tmp/final_rules.xml
RULES_CONTENT=$(cat /tmp/final_rules.xml)

# 2. Perform Dynamic Verification using wazuh-logtest
# We script a Python interaction with wazuh-logtest inside the container
# to simulate the sequence of events.

cat > /tmp/verify_rule.py << 'EOF'
import json
import sys
import subprocess
import time

def run_logtest(events):
    # Prepare input for wazuh-logtest
    input_str = "\n".join(events) + "\n"
    
    # Run wazuh-logtest inside the container
    # We use docker exec -i to pipe input
    cmd = ["docker", "exec", "-i", "wazuh-wazuh.manager-1", "/var/ossec/bin/wazuh-logtest"]
    
    try:
        process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(input=input_str)
        
        results = []
        # Parse JSON output (one JSON object per line)
        for line in stdout.splitlines():
            try:
                data = json.loads(line)
                results.append(data)
            except json.JSONDecodeError:
                continue
        return results
    except Exception as e:
        print(f"Error running logtest: {e}", file=sys.stderr)
        return []

# Define test logs
# Timestamps aren't strictly parsed by logtest unless configured, 
# but the sequence matters for correlation.
logs = [
    # Event 1: User Created (SID 5902)
    "Mar 10 10:00:00 ubuntu useradd[12345]: new user: name=ephemeral_test, UID=1001, GID=1001, home=/home/ephemeral_test, shell=/bin/bash",
    # Event 2: User Deleted (SID 5904) - Should trigger custom rule 100050
    "Mar 10 10:00:10 ubuntu userdel[12345]: delete user 'ephemeral_test'"
]

results = run_logtest(logs)

rule_fired = False
fired_rule_id = None
fired_rule_level = 0

if len(results) >= 2:
    last_event = results[-1]
    if 'rule' in last_event:
        fired_rule_id = last_event['rule'].get('id')
        fired_rule_level = last_event['rule'].get('level')
        
        # Check if our target rule fired
        if fired_rule_id == "100050":
            rule_fired = True

# Also run a negative test (delete without create)
negative_logs = [
    "Mar 10 11:00:00 ubuntu userdel[9999]: delete user 'isolated_user'"
]
neg_results = run_logtest(negative_logs)
negative_test_passed = True
if neg_results:
    neg_rule = neg_results[0].get('rule', {}).get('id')
    if neg_rule == "100050":
        negative_test_passed = False # Should NOT fire on isolated delete

output = {
    "dynamic_test_fired": rule_fired,
    "fired_rule_id": fired_rule_id,
    "fired_rule_level": fired_rule_level,
    "negative_test_passed": negative_test_passed,
    "logtest_output_summary": [r.get('rule', {}).get('id') for r in results]
}

print(json.dumps(output))
EOF

echo "Running dynamic verification..."
DYNAMIC_RESULT=$(python3 /tmp/verify_rule.py)
echo "Dynamic Result: $DYNAMIC_RESULT"

# 3. Check if Wazuh Manager is running
MANAGER_RUNNING=$(docker ps | grep "wazuh.manager" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rules_content": $(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$RULES_CONTENT"),
    "manager_running": $MANAGER_RUNNING,
    "dynamic_verification": $DYNAMIC_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json