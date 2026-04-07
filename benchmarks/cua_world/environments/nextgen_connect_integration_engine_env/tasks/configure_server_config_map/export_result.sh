#!/bin/bash
echo "=== Exporting Configuration Map task result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch the current configuration map via REST API
echo "Fetching configuration map from API..."
CONFIG_MAP_XML=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/xml" \
    "https://localhost:8443/api/server/configurationMap" 2>/dev/null)

# Verify against Database as a secondary check
# The configuration is serialized in the 'configuration' table
DB_CONFIG_CHECK=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c \
    "SELECT data FROM configuration WHERE category = 'configurationMap' LIMIT 1;" 2>/dev/null)

# Use embedded Python to parse the XML and generate a clean JSON result
# This ensures the verifier receives structured data
python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    xml_content = '''$CONFIG_MAP_XML'''
    db_content = '''$DB_CONFIG_CHECK'''
    
    result = {
        'entries': {},
        'count': 0,
        'db_persistence_verified': False,
        'task_start': $TASK_START,
        'task_end': $TASK_END
    }

    if xml_content.strip():
        try:
            root = ET.fromstring(xml_content)
            # Iterate through entries
            # Structure: <map><entry><string>KEY</string><com.mirth.connect.util.ConfigurationProperty><value>VAL</value><comment>CMT</comment>...</com.mirth.connect.util.ConfigurationProperty></entry></map>
            for entry in root.findall('.//entry'):
                key_elem = entry.find('string')
                prop_elem = entry.find('com.mirth.connect.util.ConfigurationProperty')
                
                if key_elem is not None and prop_elem is not None:
                    key = key_elem.text.strip() if key_elem.text else ''
                    
                    value_elem = prop_elem.find('value')
                    value = value_elem.text.strip() if value_elem is not None and value_elem.text else ''
                    
                    comment_elem = prop_elem.find('comment')
                    comment = comment_elem.text.strip() if comment_elem is not None and comment_elem.text else ''
                    
                    result['entries'][key] = {
                        'value': value,
                        'comment': comment
                    }
            
            result['count'] = len(result['entries'])
        except ET.ParseError:
            result['error'] = 'XML Parse Error'

    # Check database persistence
    # Simple check: do the keys exist in the DB blob?
    if db_content and len(result['entries']) > 0:
        keys_found_in_db = 0
        for key in result['entries'].keys():
            if key in db_content:
                keys_found_in_db += 1
        
        # If we found at least half the keys in the DB blob, we consider it persisted
        if keys_found_in_db >= len(result['entries']) / 2:
            result['db_persistence_verified'] = True

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/parsed_result.json

# Safely move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/parsed_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="