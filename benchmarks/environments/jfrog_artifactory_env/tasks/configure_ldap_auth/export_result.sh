#!/bin/bash
set -e
echo "=== Exporting LDAP configuration result ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Retrieve Final Configuration
# ==============================================================================
CONFIG_XML=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" 2>/dev/null)

if [ -z "$CONFIG_XML" ]; then
    echo "ERROR: Could not retrieve Artifactory configuration"
    # Create empty result
    echo "{}" > /tmp/task_result.json
    exit 0
fi

# Save XML for debugging
echo "$CONFIG_XML" > /tmp/final_config.xml

# ==============================================================================
# Parse LDAP Settings into JSON
# We do this inside the container to provide a clean JSON to the verifier
# ==============================================================================
python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('/tmp/final_config.xml')
    root = tree.getroot()
    
    # Handle namespace if present in Artifactory XML
    ns = ''
    if root.tag.startswith('{'):
        ns = root.tag.split('}')[0] + '}'
    
    # Find our specific LDAP setting
    ldap_settings = []
    found_target = False
    
    # Helper to safe get text
    def get_text(elem, path):
        node = elem.find(ns + path) if ns else elem.find(path)
        return node.text.strip() if node is not None and node.text else ''
        
    target_data = {}
    
    # Iterate all ldapSetting elements
    for ldap in root.iter(ns + 'ldapSetting') if ns else root.iter('ldapSetting'):
        key = get_text(ldap, 'key')
        
        # We are looking specifically for 'corporate-ldap' as per task specs
        if key == 'corporate-ldap':
            found_target = True
            target_data = {
                'key': key,
                'ldapUrl': get_text(ldap, 'ldapUrl'),
                'userDnPattern': get_text(ldap, 'userDnPattern'),
                'emailAttribute': get_text(ldap, 'emailAttribute'),
                'autoCreateUser': get_text(ldap, 'autoCreateUser'),
                # Nested search config
                'searchFilter': '',
                'searchBase': '',
                'managerDn': '',
                'searchSubTree': ''
            }
            
            # Search settings are usually nested in <search>
            search = ldap.find(ns + 'search') if ns else ldap.find('search')
            if search is not None:
                target_data['searchFilter'] = get_text(search, 'searchFilter')
                target_data['searchBase'] = get_text(search, 'searchBase')
                target_data['managerDn'] = get_text(search, 'managerDn')
                target_data['searchSubTree'] = get_text(search, 'searchSubTree')
            
            break
            
    result = {
        'found': found_target,
        'config': target_data,
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'screenshot_exists': True
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    # Fallback error JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'found': False}, f)
"

# Set permissions so copy_from_env can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="