#!/bin/bash
set -e
echo "=== Exporting Configure VirusTotal Integration results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Current ossec.conf content and hash
echo "Reading final configuration..."
docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/ossec.conf > /tmp/final_ossec.conf 2>/dev/null || echo "" > /tmp/final_ossec.conf
CURRENT_MD5=$(md5sum /tmp/final_ossec.conf 2>/dev/null | awk '{print $1}' || echo "0")
INITIAL_MD5=$(cat /tmp/initial_ossec_md5.txt 2>/dev/null || echo "0")

# Check if file changed
CONFIG_MODIFIED="false"
if [ "$CURRENT_MD5" != "$INITIAL_MD5" ] && [ "$INITIAL_MD5" != "0" ]; then
    CONFIG_MODIFIED="true"
fi

# 3. Check Manager Service Status
echo "Checking manager status..."
MANAGER_STATUS_OUTPUT=$(docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null || echo "docker_exec_failed")
MANAGER_RUNNING="false"
if echo "$MANAGER_STATUS_OUTPUT" | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# 4. Check API Configuration (Does the API see the integration?)
echo "Querying API for integration config..."
API_INTEGRATION_FOUND="false"
API_TOKEN=$(get_api_token 2>/dev/null || echo "")

if [ -n "$API_TOKEN" ]; then
    # Query the manager configuration via API
    # Section 'integration' returns all configured integrations
    API_CONFIG=$(curl -sk -X GET "${WAZUH_API_URL}/manager/configuration?pretty=true&section=integration" \
        -H "Authorization: Bearer ${API_TOKEN}" 2>/dev/null || echo "")
    
    # Check if 'virustotal' appears in the API response
    # This confirms the config is valid AND loaded
    if echo "$API_CONFIG" | grep -q "virustotal"; then
        API_INTEGRATION_FOUND="true"
    fi
else
    echo "WARNING: Could not get API token"
fi

# 5. Extract specific XML values for verification
# We use Python to parse the gathered config file to ensure we get specific values
# rather than just grepping, to handle XML structure correctly.
# We output a small JSON object with the parsed fields.
python3 -c "
import sys, re, json

try:
    with open('/tmp/final_ossec.conf', 'r') as f:
        content = f.read()

    # Find the integration block for virustotal
    # Looks for <integration>...<name>virustotal</name>...</integration>
    # Note: XML elements can be in any order inside integration
    match = re.search(r'<integration>(.*?)</integration>', content, re.DOTALL)
    
    found_vt = False
    api_key = ''
    group = ''
    level = ''
    fmt = ''
    
    # Iterate through all integration blocks to find virustotal
    integrations = re.findall(r'<integration>(.*?)</integration>', content, re.DOTALL)
    for block in integrations:
        if '<name>virustotal</name>' in block:
            found_vt = True
            
            # Extract fields
            m_key = re.search(r'<api_key>(.*?)</api_key>', block)
            if m_key: api_key = m_key.group(1).strip()
            
            m_group = re.search(r'<group>(.*?)</group>', block)
            if m_group: group = m_group.group(1).strip()
            
            m_level = re.search(r'<level>(.*?)</level>', block)
            if m_level: level = m_level.group(1).strip()
            
            m_fmt = re.search(r'<alert_format>(.*?)</alert_format>', block)
            if m_fmt: fmt = m_fmt.group(1).strip()
            
            break
            
    result = {
        'found_block': found_vt,
        'api_key': api_key,
        'group': group,
        'level': level,
        'format': fmt
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e), 'found_block': False}))
" > /tmp/parsed_config.json

# 6. Combine everything into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

# Load parsed config
try:
    with open('/tmp/parsed_config.json', 'r') as f:
        parsed = json.load(f)
except:
    parsed = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'config_modified': $CONFIG_MODIFIED == True,
    'manager_running': $MANAGER_RUNNING == True,
    'api_integration_found': $API_INTEGRATION_FOUND == True,
    'xml_parsed': parsed
}

print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"
rm -f /tmp/parsed_config.json /tmp/final_ossec.conf

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="