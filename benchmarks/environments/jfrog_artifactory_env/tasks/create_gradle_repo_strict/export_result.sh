#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Repository Configuration
# Artifactory OSS 7.x often restricts GET /api/repositories/{key} to Pro.
# However, GET /api/system/configuration returns the full config XML, which allows us
# to inspect detailed settings like checksum policies on OSS.

echo "Fetching system configuration..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /tmp/system_config.xml

# 3. Parse XML to JSON using Python
# We extract specific fields for the 'gradle-libs-local' repository
python3 -c "
import xml.etree.ElementTree as ET
import json
import sys

try:
    tree = ET.parse('/tmp/system_config.xml')
    root = tree.getroot()
    
    result = {
        'repo_exists': False,
        'package_type': None,
        'checksum_policy': None,
        'repo_layout': None
    }
    
    # Namespace handling might be needed depending on Artifactory version, 
    # but usually FindAll works with wildcards or direct tags in this XML structure.
    # Searching localRepositories list
    for repo in root.findall('.//localRepository'):
        key = repo.find('key')
        if key is not None and key.text == 'gradle-libs-local':
            result['repo_exists'] = True
            
            # Check package type (sometimes stored as type or inferred from layout)
            type_node = repo.find('type')
            if type_node is not None:
                result['package_type'] = type_node.text.lower()
                
            # Check layout ref (Gradle repos usually use gradle-default)
            layout_node = repo.find('repoLayoutRef')
            if layout_node is not None:
                result['repo_layout'] = layout_node.text
                
            # Check Checksum Policy
            # 'client-checksums' = Verify against client
            # 'server-generated-checksums' = Trust server (default)
            policy_node = repo.find('checksumPolicyType')
            if policy_node is not None:
                result['checksum_policy'] = policy_node.text
            else:
                result['checksum_policy'] = 'default'
            break
            
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    error_res = {'error': str(e), 'repo_exists': False}
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(error_res, f)
"

# Set permissions so verify_task can read it
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png

echo "Export complete. Result:"
cat /tmp/task_result.json