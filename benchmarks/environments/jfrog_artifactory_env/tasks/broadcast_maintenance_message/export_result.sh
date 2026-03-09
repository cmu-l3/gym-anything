#!/bin/bash
echo "=== Exporting broadcast_maintenance_message result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of banner)
take_screenshot /tmp/task_final.png

# 2. Extract System Configuration via API
# We need to check if the message is set in the backend
echo "Fetching system configuration..."
CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# 3. Parse the XML to extract relevant fields using Python
# We extract: enabled, message, color
python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    xml_data = sys.stdin.read()
    root = ET.fromstring(xml_data)
    
    # Navigate to systemMessage tag
    # Structure is usually <config><systemMessage><enabled>...</enabled>...</systemMessage></config>
    sys_msg = root.find('systemMessage')
    
    result = {
        'enabled': False,
        'message': '',
        'color': ''
    }
    
    if sys_msg is not None:
        enabled_tag = sys_msg.find('enabled')
        message_tag = sys_msg.find('message')
        color_tag = sys_msg.find('color')
        
        if enabled_tag is not None:
            result['enabled'] = (enabled_tag.text == 'true')
        if message_tag is not None:
            result['message'] = message_tag.text or ''
        if color_tag is not None:
            result['color'] = color_tag.text or ''
            
    # Save to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
        
except Exception as e:
    print(f'Error parsing XML: {e}', file=sys.stderr)
    # Fallback empty result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

" <<< "$CONFIG_XML"

# 4. Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Append timestamps to the JSON (using jq or python)
python3 -c "
import json
import os

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    
    data['task_start'] = $TASK_START
    data['task_end'] = $TASK_END
    data['screenshot_path'] = '/tmp/task_final.png'
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(e)
"

# 5. Output for debug
echo "Exported Data:"
cat /tmp/task_result.json
echo ""

echo "=== Export complete ==="