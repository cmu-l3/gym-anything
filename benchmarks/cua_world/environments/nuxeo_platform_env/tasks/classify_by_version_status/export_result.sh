#!/bin/bash
echo "=== Exporting classify_by_version_status results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# Query Nuxeo for the final state of documents
# ---------------------------------------------------------------------------
# We need to find where the documents are now.
# Using NXQL is robust against moves.

# Query all children of Holding-Area (recursive) to find our specific docs
QUERY="SELECT * FROM Document WHERE ecm:name IN ('Product-Specs', 'User-Guide', 'Marketing-Flyer', 'Internal-Memo') AND ecm:path STARTSWITH '/default-domain/workspaces/Holding-Area' AND ecm:isTrashed = 0"

# Execute Query
JSON_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -G \
    --data-urlencode "query=$QUERY" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute")

# Also check what is left in the root of Holding-Area (should be empty of files)
ROOT_CHILDREN=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Holding-Area/@children")

# Save raw responses for debug/verification
echo "$JSON_RESPONSE" > /tmp/nuxeo_docs_state.json
echo "$ROOT_CHILDREN" > /tmp/nuxeo_root_children.json

# Process into a clean result JSON using python
python3 -c "
import json
import sys
import os

try:
    with open('/tmp/nuxeo_docs_state.json') as f:
        docs_data = json.load(f)
    
    with open('/tmp/nuxeo_root_children.json') as f:
        root_data = json.load(f)

    results = {
        'documents': {},
        'root_clean': True,
        'task_info': {
            'start': $TASK_START,
            'end': $TASK_END
        }
    }

    # Map documents to their parent paths
    for doc in docs_data.get('entries', []):
        name = doc.get('name')
        path = doc.get('path', '')
        parent_ref = doc.get('parentRef')
        
        # Determine parent folder name from path
        # Path format: /default-domain/workspaces/Holding-Area/Released/DocName
        parent_folder = 'unknown'
        if '/Released/' in path:
            parent_folder = 'Released'
        elif '/Drafts/' in path:
            parent_folder = 'Drafts'
        elif path.endswith('/Holding-Area/' + name):
            parent_folder = 'Holding-Area'
            
        results['documents'][name] = {
            'path': path,
            'parent_folder': parent_folder,
            'uid': doc.get('uid')
        }

    # Check root cleanliness
    # Root should only contain 'Released' and 'Drafts' folders
    allowed_names = ['Released', 'Drafts']
    for child in root_data.get('entries', []):
        child_name = child.get('name')
        child_type = child.get('type')
        if child_name not in allowed_names:
            # If it's one of our target docs still here, root is not clean
            results['root_clean'] = False
            break

    # Save to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(results, f, indent=2)

except Exception as e:
    print(f'Error processing results: {e}')
    # Create empty error result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="