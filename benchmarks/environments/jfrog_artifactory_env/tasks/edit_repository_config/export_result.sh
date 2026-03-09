#!/bin/bash
echo "=== Exporting edit_repository_config result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Configuration
REPO_KEY="example-repo-local"
RESULT_FILE="/tmp/task_result.json"

# 1. Get detailed repository info
# In Artifactory OSS, this might return 400 for some versions, but we try anyway.
echo "Fetching repository details..."
REPO_DETAIL_JSON=$(get_repo_info "$REPO_KEY")
echo "Detail response code: $?"

# 2. Get repository list (Backup for description field)
echo "Fetching repository list..."
REPO_LIST_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/repositories")

# 3. Check modification via timestamps is hard in Artifactory API, 
# so we rely on content verification.

# Create result JSON
# Use a python script to assemble the JSON safely to handle quoting issues
python3 -c "
import json
import os
import sys

try:
    detail_raw = '''$REPO_DETAIL_JSON'''
    list_raw = '''$REPO_LIST_JSON'''
    
    result = {
        'repo_key': '$REPO_KEY',
        'detail': {},
        'list_entry': {},
        'detail_fetched': False,
        'screenshot_path': '/tmp/task_final.png',
        'task_start': 0,
        'task_end': 0
    }

    # Parse Detail
    try:
        if detail_raw and '{' in detail_raw:
            result['detail'] = json.loads(detail_raw)
            result['detail_fetched'] = True
    except Exception as e:
        print(f'Error parsing detail JSON: {e}', file=sys.stderr)

    # Parse List
    try:
        if list_raw and '[' in list_raw:
            repo_list = json.loads(list_raw)
            # Find our specific repo
            for r in repo_list:
                if r.get('key') == '$REPO_KEY':
                    result['list_entry'] = r
                    break
    except Exception as e:
        print(f'Error parsing list JSON: {e}', file=sys.stderr)

    # Timestamps
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start'] = int(f.read().strip())
    except:
        pass
        
    import time
    result['task_end'] = int(time.time())

    # Write output
    with open('$RESULT_FILE', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('JSON export successful')

except Exception as e:
    print(f'Fatal export error: {e}', file=sys.stderr)
"

# Handle permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE" 2>/dev/null
echo "=== Export complete ==="