#!/bin/bash
echo "=== Exporting Data Pruner Configuration Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Create Python script to query API and build JSON result
cat > /tmp/check_config.py << 'EOF'
import sys
import json
import requests
import xml.etree.ElementTree as ET

# Configuration
BASE_URL = "https://localhost:8443/api"
AUTH = ("admin", "admin")
HEADERS = {"X-Requested-With": "OpenAPI", "Accept": "application/json"}
VERIFY_SSL = False

results = {}

try:
    # 1. Get Data Pruner Properties
    # Note: Properties endpoint often returns map, not standard JSON object structure in all versions
    # We'll request JSON but be prepared to parse
    resp = requests.get(f"{BASE_URL}/extensions/Data%20Pruner/properties", auth=AUTH, headers=HEADERS, verify=VERIFY_SSL)
    if resp.status_code == 200:
        props = resp.json()
        # NextGen Connect properties maps are often {"map": {"entry": [{"string": ["key", "value"]}, ...]}} or simple dicts depending on version
        # Let's normalize to a simple dict
        pruner_config = {}
        
        # Handle different serialization formats
        if isinstance(props, dict):
            # If it's the "map/entry" format
            if 'map' in props and 'entry' in props['map']:
                entries = props['map']['entry']
                if isinstance(entries, list):
                    for entry in entries:
                        if 'string' in entry and isinstance(entry['string'], list) and len(entry['string']) == 2:
                            pruner_config[entry['string'][0]] = entry['string'][1]
            # If it's a direct dictionary (less common for properties in Mirth 3/4 but possible)
            else:
                pruner_config = props
        
        results['pruner_config'] = pruner_config
    else:
        results['pruner_error'] = f"HTTP {resp.status_code}: {resp.text}"

    # 2. Get Channels to check pruning settings
    # We need to find the IDs for "Regional_ADT_Feed" and "Lab_Orders_Interface"
    resp = requests.get(f"{BASE_URL}/channels", auth=AUTH, headers=HEADERS, verify=VERIFY_SSL)
    if resp.status_code == 200:
        channels_list = resp.json()
        if 'list' in channels_list and 'channel' in channels_list['list']:
             channels = channels_list['list']['channel']
             # Single channel might be a dict, multiple a list
             if isinstance(channels, dict):
                 channels = [channels]
        else:
             channels = []

        channel_configs = {}
        
        for ch in channels:
            name = ch.get('name')
            if name in ["Regional_ADT_Feed", "Lab_Orders_Interface"]:
                # Extract pruning settings
                # Mirth JSON structure: channel -> properties -> (various fields)
                # But pruning settings are often in channel -> exportData -> metadata -> pruningSettings?
                # Actually, in modern Mirth, it's in channel -> properties (root level of properties object)
                # Let's look at the structure.
                
                # In XML it is <channel><properties><removeContentOnCompletion>...</properties></channel>
                # But spec says pruning is distinct.
                # In 4.x: <channel>...<properties>...<pruneMetaDataDays>...
                
                # Let's fetch the XML for the channel to be sure, JSON model can be tricky with polymorphism
                ch_id = ch.get('id')
                xml_resp = requests.get(f"{BASE_URL}/channels/{ch_id}", auth=AUTH, headers={"X-Requested-With": "OpenAPI", "Accept": "application/xml"}, verify=VERIFY_SSL)
                if xml_resp.status_code == 200:
                    root = ET.fromstring(xml_resp.text)
                    # Find properties element under channel
                    # Pruning settings are direct children of the <properties> element in 4.x?
                    # No, usually: <channel>...<properties>...<pruneMetaDataDays>7</pruneMetaDataDays>...</properties>
                    
                    props_node = root.find('properties')
                    config = {}
                    if props_node is not None:
                        for child in props_node:
                            # Try to get pruning fields
                            if child.tag in ['pruneMetaDataDays', 'pruneContentDays', 'archiveEnabled']:
                                config[child.tag] = child.text
                            # Also check if they are integers behaving like booleans or strings
                    
                    channel_configs[name] = config

        results['channels'] = channel_configs

except Exception as e:
    results['script_error'] = str(e)

# Add timestamp
import time
results['timestamp'] = time.time()

print(json.dumps(results, indent=2))
EOF

# Execute Python script and save result
python3 /tmp/check_config.py > /tmp/task_result.json

# Copy result to final location with proper permissions
rm -f /tmp/configure_data_pruner_retention_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/configure_data_pruner_retention_result.json
chmod 666 /tmp/configure_data_pruner_retention_result.json

echo "Result saved to /tmp/configure_data_pruner_retention_result.json"
cat /tmp/configure_data_pruner_retention_result.json
echo "=== Export complete ==="