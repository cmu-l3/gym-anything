#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Data via Nuxeo REST API
# We need to see what's inside the Target Section (HR-Intranet)
SECTION_PATH="/default-domain/sections/HR-Intranet"

# Query children of the section
# Enriched with 'dublincore' to get version info, title, description
echo "Querying section content..."
CHILDREN_JSON=$(nuxeo_api GET "/path$SECTION_PATH/@children")

# Also get the Source Document state for reference
SOURCE_PATH="/default-domain/workspaces/HR-Workspace/Remote-Work-Policy"
SOURCE_JSON=$(nuxeo_api GET "/path$SOURCE_PATH")

# 3. Construct Result JSON
# We use Python to parse the API response and create a clean result file
python3 -c "
import sys, json, os

try:
    children_resp = json.loads('''$CHILDREN_JSON''')
    source_resp = json.loads('''$SOURCE_JSON''')
    
    entries = children_resp.get('entries', [])
    
    proxies_found = []
    for doc in entries:
        # Check if it's a proxy
        is_proxy = doc.get('isProxy', False)
        title = doc.get('title', '')
        
        # Nuxeo stores version info in properties or facets
        # For a proxy, check 'renderView' or 'facets' or specific properties depending on API version
        # Usually 'ecm:proxyVersion' is NOT directly in properties in standard JSON marshalling unless requested
        # But for verification, let's look at the document version labels
        
        # In Nuxeo REST API, standard doc response includes 'versionLabel'
        version_label = doc.get('versionLabel', '0.0')
        
        proxies_found.append({
            'uid': doc.get('uid'),
            'title': title,
            'is_proxy': is_proxy,
            'version_label': version_label,
            'path': doc.get('path')
        })

    result = {
        'section_children': proxies_found,
        'source_doc_version': source_resp.get('versionLabel', 'unknown'),
        'timestamp': $(date +%s)
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Write robust fallback
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'section_children': []}, f)
"

# 4. Save screenshot path to result (optional, verifier knows where to look)
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="