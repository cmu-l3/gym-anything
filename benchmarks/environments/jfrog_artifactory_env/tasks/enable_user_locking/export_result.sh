#!/bin/bash
echo "=== Exporting Enable User Locking Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Fetch System Configuration
# This is the ground truth for verification
echo "Fetching system configuration..."
CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# Save raw XML for debugging
echo "$CONFIG_XML" > /tmp/final_config.xml

# 3. Parse relevant fields from XML
# We use grep/sed/awk or python to extract specific values because the XML structure is complex
# <security>
#   <userLockPolicy>
#     <enabled>true</enabled>
#     <maxLoginAttempts>3</maxLoginAttempts>
#     <lockOutTime>1</lockOutTime>
#   </userLockPolicy>
# </security>

PARSED_CONFIG=$(echo "$CONFIG_XML" | python3 -c "
import sys
import xml.etree.ElementTree as ET
import json

try:
    # Read from stdin
    xml_data = sys.stdin.read()
    root = ET.fromstring(xml_data)
    
    # Navigate to security > userLockPolicy
    security = root.find('security')
    policy = security.find('userLockPolicy') if security is not None else None
    
    result = {
        'found_policy': False,
        'enabled': False,
        'max_attempts': 0,
        'lockout_time': 0
    }
    
    if policy is not None:
        result['found_policy'] = True
        
        enabled_elem = policy.find('enabled')
        if enabled_elem is not None:
            result['enabled'] = (enabled_elem.text.lower() == 'true')
            
        attempts_elem = policy.find('maxLoginAttempts')
        if attempts_elem is not None:
            result['max_attempts'] = int(attempts_elem.text)
            
        time_elem = policy.find('lockOutTime')
        if time_elem is not None:
            result['lockout_time'] = int(time_elem.text)

    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e), 'found_policy': False}))
")

echo "Parsed configuration: $PARSED_CONFIG"

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_xml_retrieved": $([ -n "$CONFIG_XML" ] && echo "true" || echo "false"),
    "parsed_config": $PARSED_CONFIG
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="