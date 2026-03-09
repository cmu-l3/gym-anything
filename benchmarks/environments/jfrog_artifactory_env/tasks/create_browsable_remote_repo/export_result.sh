#!/bin/bash
echo "=== Exporting create_browsable_remote_repo result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Repository Configuration
# In Artifactory OSS, individual repo GET /api/repositories/{key} is often restricted (Pro-only).
# However, /api/system/configuration returns the full system config XML, which allows us to verify details.
echo "Fetching system configuration..."

CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# Use Python to parse the XML and extract the specific repo details
# We look for <remoteRepository> blocks where <key> is maven-explorer
python3 -c "
import sys
import json
import xml.etree.ElementTree as ET

try:
    xml_data = sys.stdin.read()
    root = ET.fromstring(xml_data)
    
    repo_found = False
    repo_details = {
        'exists': False,
        'type': None,
        'url': None,
        'listRemoteFolderItems': False, # Default is false
        'description': None,
        'packageType': None # XML might not explicitly show packageType if default, checking context
    }

    # Iterate over remote repositories
    # Structure: <config><remoteRepositories><remoteRepository>...
    remote_repos = root.find('remoteRepositories')
    if remote_repos is not None:
        for repo in remote_repos.findall('remoteRepository'):
            key_elem = repo.find('key')
            if key_elem is not None and key_elem.text == 'maven-explorer':
                repo_found = True
                repo_details['exists'] = True
                repo_details['type'] = 'remote' # implied by parent tag
                
                # Get URL
                url_elem = repo.find('url')
                repo_details['url'] = url_elem.text if url_elem is not None else ''
                
                # Get List Remote Folder Items
                list_elem = repo.find('listRemoteFolderItems')
                # In XML, it's usually 'true' or 'false' text
                if list_elem is not None and list_elem.text and list_elem.text.lower() == 'true':
                    repo_details['listRemoteFolderItems'] = True
                else:
                    repo_details['listRemoteFolderItems'] = False
                    
                # Get Description
                desc_elem = repo.find('description')
                repo_details['description'] = desc_elem.text if desc_elem is not None else ''

                # Package Type verification usually implied by remoteRepo config or specific type tag
                # In config XML, <type> often holds the package type (e.g. 'maven')
                type_elem = repo.find('type')
                repo_details['packageType'] = type_elem.text if type_elem is not None else 'unknown'
                
                break

    # Save to JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(repo_details, f, indent=2)

except Exception as e:
    # Fallback error JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'exists': False, 'error': str(e)}, f)

" <<< "$CONFIG_XML"

# Check if app was running (Firefox)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Add timestamp and metadata to the result file
# We read the python output, add more fields, and write it back
python3 -c "
import json
import os
import time

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {'exists': False}

data['task_end_timestamp'] = time.time()
data['app_was_running'] = '$APP_RUNNING' == 'true'
data['screenshot_path'] = '/tmp/task_final.png'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="