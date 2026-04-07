#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting results for configure_project_custom_fields ==="

# 1. Capture final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. API Retrieval
# We need to export:
# a) The definitions of the custom fields (to check types, formats, etc.)
# b) The project details (to check if values were applied)

API_KEY=$(redmine_admin_api_key)
PROJECT_IDENTIFIER="mobile-banking-upgrade"

# Fetch all custom fields
curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/custom_fields.json" > /tmp/custom_fields_raw.json

# Fetch the specific project with custom fields included
curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/projects/$PROJECT_IDENTIFIER.json?include=custom_fields" > /tmp/project_raw.json

# 3. Combine into a single result file
# We use python to safely merge these JSONs
python3 -c "
import json
import os
import time

try:
    with open('/tmp/custom_fields_raw.json') as f:
        cfs = json.load(f)
    with open('/tmp/project_raw.json') as f:
        proj = json.load(f)
        
    result = {
        'custom_fields': cfs.get('custom_fields', []),
        'project': proj.get('project', {}),
        'timestamp': time.time(),
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(json.dumps({'error': str(e)}))
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"