#!/bin/bash
echo "=== Exporting data_spillage_remediation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Ensure Splunk is running
if ! splunk_is_running; then
    echo "Splunk not running. Starting..."
    /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
    sleep 20
fi

# Helper Python script to parse JSON Lines from Splunk export endpoint
cat > /tmp/parse_count.py << 'EOF'
import sys, json
try:
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        data = json.loads(line)
        if 'result' in data and 'count' in data['result']:
            print(str(data['result']['count']))
            sys.exit(0)
    print("error")
except Exception:
    print("error")
EOF

# 1. Check if admin has can_delete role
HAS_CAN_DELETE="false"
ADMIN_ROLES=$(curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/authentication/users/admin?output_mode=json 2>/dev/null)
if echo "$ADMIN_ROLES" | grep -q '"can_delete"'; then
    HAS_CAN_DELETE="true"
fi

# 2. Check historical leaked data (Should be 0 if deleted)
LEAKED_COUNT=$(curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/search/jobs/export" -d search="search index=web_logs sourcetype=apache_leak \"password=\" | stats count" -d output_mode=json 2>/dev/null | python3 /tmp/parse_count.py)

# 3. Check collateral data (Should be >0)
COLLATERAL_COUNT=$(curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/search/jobs/export" -d search="search index=web_logs sourcetype=apache_leak NOT \"password=\" | stats count" -d output_mode=json 2>/dev/null | python3 /tmp/parse_count.py)

# 4. Inject a new test line to verify SEDCMD
echo "192.168.1.99 - - [$(date +'%d/%b/%Y:%H:%M:%S %z')] \"POST /api/auth HTTP/1.1\" 200 123 \"user=verifier&password=TestVerif99\"" > /tmp/verify_leak.log
/opt/splunk/bin/splunk add oneshot /tmp/verify_leak.log -index web_logs -sourcetype apache_leak -auth admin:SplunkAdmin1! >/dev/null 2>&1
sleep 15 # Wait for indexing to complete

# 5. Check if cleartext test string is searchable (Should be 0 if masked)
CLEARTEXT_COUNT=$(curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/search/jobs/export" -d search="search index=web_logs sourcetype=apache_leak TestVerif99 | stats count" -d output_mode=json 2>/dev/null | python3 /tmp/parse_count.py)

# 6. Check if REDACTED is found (Should be >0 if masked)
REDACTED_COUNT=$(curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/services/search/jobs/export" -d search="search index=web_logs sourcetype=apache_leak user=verifier REDACTED | stats count" -d output_mode=json 2>/dev/null | python3 /tmp/parse_count.py)

# 7. Check btool for SEDCMD configuration
BTOOL_SEDCMD=$(/opt/splunk/bin/splunk cmd btool props list apache_leak 2>/dev/null | grep SEDCMD || echo "")

# Write output to JSON using python to handle any edge-case string escaping securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
export HAS_CAN_DELETE LEAKED_COUNT COLLATERAL_COUNT CLEARTEXT_COUNT REDACTED_COUNT BTOOL_SEDCMD
python3 -c "
import json, os
data = {
    'has_can_delete': os.environ.get('HAS_CAN_DELETE') == 'true',
    'leaked_count': os.environ.get('LEAKED_COUNT'),
    'collateral_count': os.environ.get('COLLATERAL_COUNT'),
    'cleartext_count': os.environ.get('CLEARTEXT_COUNT'),
    'redacted_count': os.environ.get('REDACTED_COUNT'),
    'btool_sedcmd': os.environ.get('BTOOL_SEDCMD', '')
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="