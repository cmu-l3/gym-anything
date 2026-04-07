#!/bin/bash
echo "=== Exporting Detect DNS Tunneling results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Extract Configuration Files
# We need to see if they added the <localfile> block to ossec.conf
# And if they modified decoders and rules
docker cp "${CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec.conf
docker cp "${CONTAINER}:/var/ossec/etc/decoders/local_decoder.xml" /tmp/local_decoder.xml
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules.xml

# 2. Run Verification Test using wazuh-logtest (INSIDE CONTAINER)
# This is the gold standard: does the actual engine parse and trigger?

# Test case 1: Malicious (Long domain)
MALICIOUS_LOG='2023-10-27T14:02:15 dns-edge-01 query_log: client_ip="192.168.1.52" domain="very-long-encoded-string-that-looks-like-base64-exfiltration-data.attacker-site.com" type="TXT"'

# Test case 2: Benign (Short domain)
BENIGN_LOG='2023-10-27T14:02:11 dns-edge-01 query_log: client_ip="192.168.1.50" domain="google.com" type="A"'

echo "Running wazuh-logtest verification..."

# We use python inside the container to interact with wazuh-logtest socket or binary if possible,
# but the binary reads from stdin.
# JSON output (-j) is best for parsing.

LOGTEST_MALICIOUS=$(echo "$MALICIOUS_LOG" | docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest -j 2>/dev/null)
LOGTEST_BENIGN=$(echo "$BENIGN_LOG" | docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest -j 2>/dev/null)

# 3. Check if Wazuh manager is running
MANAGER_RUNNING=$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Compile Result JSON
# We embed the config files and logtest results into the JSON
# Python is used to safely escape strings

python3 -c "
import json
import os
import sys

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r') as f:
            return f.read()
    return ''

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'manager_running': '$MANAGER_RUNNING' == 'true',
    'ossec_conf': read_file('/tmp/ossec.conf'),
    'local_decoder': read_file('/tmp/local_decoder.xml'),
    'local_rules': read_file('/tmp/local_rules.xml'),
    'logtest_malicious_raw': '''$LOGTEST_MALICIOUS''',
    'logtest_benign_raw': '''$LOGTEST_BENIGN''',
    'screenshot_path': '/tmp/task_final.png'
}

# Try to parse logtest JSON output if valid
try:
    result['logtest_malicious'] = json.loads(result['logtest_malicious_raw'])
except:
    result['logtest_malicious'] = {}

try:
    result['logtest_benign'] = json.loads(result['logtest_benign_raw'])
except:
    result['logtest_benign'] = {}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"