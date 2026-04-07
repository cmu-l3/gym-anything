#!/bin/bash
# export_result.sh for tune_rule_false_positives

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Manager Uptime (to verify restart)
# wazuh-control status returns pid, we can check process start time or uptime
# easier: docker inspect the process start time? No, process inside container.
# We will use ps inside container.
MANAGER_PID=$(wazuh_exec pgrep wazuh-analysisd | head -n1)
if [ -n "$MANAGER_PID" ]; then
    # Get elapsed time in seconds
    MANAGER_ELAPSED=$(wazuh_exec ps -p "$MANAGER_PID" -o etimes= | tr -d ' ')
    echo "Manager elapsed time: $MANAGER_ELAPSED seconds"
else
    MANAGER_ELAPSED="999999"
    echo "Manager not running"
fi

# 3. Retrieve Rule 5402 status via API
echo "Querying Rule 5402..."
RULE_5402_JSON=$(wazuh_api GET "/rules?rule_ids=5402")

# 4. Retrieve Rule 100100 status via API
echo "Querying Rule 100100..."
RULE_100100_JSON=$(wazuh_api GET "/rules?rule_ids=100100")

# 5. Get local_rules.xml content
echo "Reading local_rules.xml..."
LOCAL_RULES_CONTENT=$(wazuh_exec cat /var/ossec/etc/rules/local_rules.xml)

# 6. Get md5 to check for changes
FINAL_MD5=$(wazuh_exec md5sum /var/ossec/etc/rules/local_rules.xml | awk '{print $1}')
INITIAL_MD5=$(cat /tmp/initial_rules_md5.txt 2>/dev/null || echo "")

# 7. Construct Result JSON
# Using python to safely generate JSON with potentially multi-line string content
python3 -c "
import json
import os
import sys

def safe_load(json_str):
    try:
        return json.loads(json_str)
    except:
        return {}

rule_5402_data = safe_load('''$RULE_5402_JSON''')
rule_100100_data = safe_load('''$RULE_100100_JSON''')
rules_content = '''$LOCAL_RULES_CONTENT'''

# Extract simplified rule info
r5402 = {}
items_5402 = rule_5402_data.get('data', {}).get('affected_items', [])
if items_5402:
    r5402 = items_5402[0]

r100100 = {}
items_100100 = rule_100100_data.get('data', {}).get('affected_items', [])
if items_100100:
    r100100 = items_100100[0]

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'manager_uptime_sec': int('$MANAGER_ELAPSED') if '$MANAGER_ELAPSED'.isdigit() else -1,
    'file_changed': ('$INITIAL_MD5' != '$FINAL_MD5'),
    'rule_5402': {
        'exists': bool(r5402),
        'level': r5402.get('level'),
        'filename': r5402.get('filename'),
        'details': r5402.get('details', {})
    },
    'rule_100100': {
        'exists': bool(r100100),
        'level': r100100.get('level'),
        'groups': r100100.get('groups', []),
        'pci_dss': r100100.get('pci_dss', []),
        'details': r100100.get('details', {}) # contains if_sid logic often
    },
    'local_rules_content': rules_content,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 8. Set permissions and move
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json