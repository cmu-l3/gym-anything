#!/bin/bash
echo "=== Exporting Deprecate Repo Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot (Critical for VLM)
take_screenshot /tmp/task_final.png

# 2. Capture Repository State
# We need to verify 'blackedOut': true and 'description'.
# Strategy: Try specific API first, fallback to system config XML.

echo "Querying repository configuration..."
REPO_CONFIG_JSON=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories/example-repo-local")

# Save specific config
echo "$REPO_CONFIG_JSON" > /tmp/final_repo_config.json

# 3. Capture System Config (Fallback)
# If the specific endpoint returns 400/404/403 (common in OSS), the system config XML usually contains all repo definitions.
SYSTEM_CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")
echo "$SYSTEM_CONFIG_XML" > /tmp/final_system_config.xml

# 4. Consolidate into Result JSON
# We'll use Python to parse what we captured and create a clean result file for the verifier.
python3 -c "
import json
import sys
import re

try:
    result = {
        'timestamp': '$(date +%s)',
        'repo_exists': False,
        'blacked_out': False,
        'description': '',
        'source': 'unknown'
    }

    # Try parsing JSON first
    try:
        with open('/tmp/final_repo_config.json', 'r') as f:
            data = json.load(f)
            if 'key' in data and data['key'] == 'example-repo-local':
                result['repo_exists'] = True
                result['blacked_out'] = data.get('blackedOut', False)
                result['description'] = data.get('description', '')
                result['source'] = 'api_json'
    except:
        pass

    # If JSON didn't give us the data (e.g. error response), parse XML
    if not result['repo_exists']:
        try:
            with open('/tmp/final_system_config.xml', 'r') as f:
                xml_content = f.read()
                
            # Regex parsing for the specific repo block in XML
            # <localRepository>...<key>example-repo-local</key>...<blackedOut>true</blackedOut>...</localRepository>
            # This is rough but sufficient for verification script logic usually
            
            # Find the block for example-repo-local
            repo_block_match = re.search(r'<localRepository>.*?</localRepository>', xml_content, re.DOTALL)
            # Iterate all localRepository blocks to find the right one
            blocks = re.findall(r'<localRepository>(.*?)</localRepository>', xml_content, re.DOTALL)
            
            for block in blocks:
                if '<key>example-repo-local</key>' in block:
                    result['repo_exists'] = True
                    result['source'] = 'system_xml'
                    
                    # Check blackedOut
                    bo_match = re.search(r'<blackedOut>(.*?)</blackedOut>', block)
                    if bo_match:
                        result['blacked_out'] = (bo_match.group(1).lower() == 'true')
                    
                    # Check description
                    desc_match = re.search(r'<description>(.*?)</description>', block)
                    if desc_match:
                        result['description'] = desc_match.group(1)
                    break
        except Exception as e:
            result['xml_error'] = str(e)

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(json.dumps({'error': str(e)}))
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="