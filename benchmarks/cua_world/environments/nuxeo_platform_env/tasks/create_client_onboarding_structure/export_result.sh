#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Summary File
SUMMARY_FILE="/home/ga/onboarding_summary.json"
SUMMARY_EXISTS="false"
SUMMARY_CONTENT="{}"
if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    # Read content safely
    SUMMARY_CONTENT=$(cat "$SUMMARY_FILE")
fi

# 3. Harvest Nuxeo Structure via REST API
# We will fetch the root folder and its children to verify the structure programmatically
# outputting to a JSON structure for the verifier.

ROOT_PATH="/default-domain/workspaces/Projects/Meridian-Holdings"

# Function to get doc properties
get_doc_json() {
    local path="$1"
    curl -s -u "$NUXEO_AUTH" \
        -H "X-NXproperties: dublincore,note" \
        "$NUXEO_URL/api/v1/path$path" 2>/dev/null || echo "{}"
}

# Function to get children
get_children_json() {
    local path="$1"
    curl -s -u "$NUXEO_AUTH" \
        -H "X-NXproperties: dublincore,note" \
        "$NUXEO_URL/api/v1/path$path/@children" 2>/dev/null || echo "{}"
}

echo "Fetching Nuxeo structure data..."

# Get Root Folder
ROOT_JSON=$(get_doc_json "$ROOT_PATH")

# Get Subfolders (Identification, Contracts, etc.)
CHILDREN_JSON=$(get_children_json "$ROOT_PATH")

# We need to inspect inside the subfolders for the Notes.
# We'll construct a simplified JSON object of the tree.
# This requires parsing the children IDs/paths and fetching their children.
# Since bash JSON parsing is hard, we'll do a simple python script to build the tree.

TREE_JSON=$(python3 -c "
import sys, json, requests
from requests.auth import HTTPBasicAuth

auth = HTTPBasicAuth('$NUXEO_ADMIN', '$NUXEO_PASS')
base_url = '$NUXEO_URL/api/v1'
root_path = '$ROOT_PATH'

def get_doc(path):
    try:
        r = requests.get(f'{base_url}/path{path}', auth=auth, headers={'X-NXproperties': 'dublincore,note'})
        if r.status_code == 200:
            return r.json()
    except:
        pass
    return None

def get_children(uid):
    try:
        r = requests.get(f'{base_url}/id/{uid}/@children', auth=auth, headers={'X-NXproperties': 'dublincore,note'})
        if r.status_code == 200:
            return r.json().get('entries', [])
    except:
        pass
    return []

result = {'root': None, 'subfolders': {}}

# Fetch root
root_doc = get_doc(root_path)
if root_doc:
    result['root'] = root_doc
    # Fetch subfolders
    subs = get_children(root_doc['uid'])
    for sub in subs:
        sub_name = sub.get('name')
        # Fetch notes inside subfolder
        notes = get_children(sub['uid'])
        result['subfolders'][sub_name] = {
            'info': sub,
            'children': notes
        }

print(json.dumps(result))
")

# 4. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "summary_file_exists": $SUMMARY_EXISTS,
    "summary_file_content": $SUMMARY_CONTENT,
    "nuxeo_structure": $TREE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="