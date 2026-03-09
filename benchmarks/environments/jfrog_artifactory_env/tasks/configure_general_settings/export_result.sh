#!/bin/bash
# Export script for configure_general_settings task
echo "=== Exporting configure_general_settings result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (Visual Evidence)
take_screenshot /tmp/task_final.png

# 2. Fetch Final Configuration via API (Programmatic Evidence)
echo "Fetching final system configuration..."
FINAL_CONFIG=$(curl -s -u admin:password "${ARTIFACTORY_URL}/artifactory/api/system/configuration")

# Save raw config for debugging (optional)
echo "$FINAL_CONFIG" > /tmp/final_config_raw.xml

# 3. Parse Configuration using Python
# We extract the specific fields: urlBase and fileUploadMaxSizeMb
python3 -c "
import sys, json, xml.etree.ElementTree as ET

result = {
    'url_base': None,
    'file_upload_max_mb': None,
    'config_retrieved': False
}

try:
    xml_data = sys.stdin.read().strip()
    if xml_data:
        root = ET.fromstring(xml_data)
        result['config_retrieved'] = True
        
        # Robust search ignoring namespaces
        for elem in root.iter():
            if elem.tag.endswith('urlBase'):
                result['url_base'] = elem.text
            elif elem.tag.endswith('fileUploadMaxSizeMb'):
                try:
                    result['file_upload_max_mb'] = int(elem.text)
                except:
                    result['file_upload_max_mb'] = elem.text

    # Read initial values for comparison
    initial_values = {}
    try:
        with open('/tmp/initial_config_values.txt', 'r') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    initial_values[k] = v
    except:
        pass
        
    result['initial_values'] = initial_values

except Exception as e:
    result['error'] = str(e)

# Output JSON
print(json.dumps(result, indent=2))
" <<< "$FINAL_CONFIG" > /tmp/task_result.json

# 4. Set permissions so the verifier can copy it
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png

echo "Export complete. Result:"
cat /tmp/task_result.json