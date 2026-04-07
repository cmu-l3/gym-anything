#!/bin/bash
echo "=== Exporting trash_and_restore_documents results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query document states via Nuxeo API
# We need to check:
# - Annual Report 2023 (Expect: isTrashed=true)
# - Project Proposal (Expect: isTrashed=true)
# - Meeting Minutes Q2 (Expect: isTrashed=false)
# - Q3 Status Report (Expect: isTrashed=false)
# - Budget Forecast 2024 (Expect: isTrashed=false)

echo "Querying document states..."

# Helper to get JSON for a path
get_doc_json() {
    local path="$1"
    curl -s -u "$NUXEO_AUTH" \
        -H "X-NXproperties: *" \
        "$NUXEO_URL/api/v1/path$path"
}

# Fetch details for all 5 docs
DOC1=$(get_doc_json "/default-domain/workspaces/Projects/Annual-Report-2023")
DOC2=$(get_doc_json "/default-domain/workspaces/Projects/Project-Proposal")
DOC3=$(get_doc_json "/default-domain/workspaces/Projects/Meeting-Minutes-Q2")
DOC4=$(get_doc_json "/default-domain/workspaces/Projects/Q3-Status-Report")
DOC5=$(get_doc_json "/default-domain/workspaces/Projects/Budget-Forecast-2024")

# Extract task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Create JSON result
# Use python to safely construct JSON from the API responses
python3 -c "
import sys, json, time

def parse_doc(json_str, name):
    try:
        data = json.loads(json_str)
        if 'status' in data and data['status'] >= 400:
            return {'name': name, 'exists': False, 'trashed': False, 'modified': 0}
        
        props = data.get('properties', {})
        # Nuxeo uses 'ecm:isTrashed' property or 'isTrashed' boolean at root depending on version
        # We check the standard boolean 'isTrashed' first, then property
        is_trashed = data.get('isTrashed', False)
        if not is_trashed and 'ecm:isTrashed' in props:
             is_trashed = props['ecm:isTrashed']
             
        # Get modification time
        mod_str = data.get('lastModified', '')
        # Simple string storage, verifier will parse if needed, or we just store string
        
        return {
            'name': name,
            'exists': True,
            'trashed': is_trashed,
            'last_modified': mod_str,
            'title': data.get('title', '')
        }
    except Exception as e:
        return {'name': name, 'exists': False, 'error': str(e)}

docs = [
    parse_doc(sys.argv[1], 'Annual Report 2023'),
    parse_doc(sys.argv[2], 'Project Proposal'),
    parse_doc(sys.argv[3], 'Meeting Minutes Q2'),
    parse_doc(sys.argv[4], 'Q3 Status Report'),
    parse_doc(sys.argv[5], 'Budget Forecast 2024')
]

result = {
    'task_start_ts': $TASK_START,
    'task_end_ts': time.time(),
    'documents': {d['name']: d for d in docs},
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" "$DOC1" "$DOC2" "$DOC3" "$DOC4" "$DOC5"

# 4. Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="