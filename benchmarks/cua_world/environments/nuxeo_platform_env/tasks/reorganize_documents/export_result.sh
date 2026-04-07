#!/bin/bash
echo "=== Exporting reorganize_documents results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# Gather Nuxeo State via API
# ---------------------------------------------------------------------------
# We need to traverse the Projects workspace and build a tree of what exists
# to verify the structure and document locations.

cat << 'PYEOF' > /tmp/gather_nuxeo_state.py
import requests
import json
import os
import time

NUXEO_URL = "http://localhost:8080/nuxeo/api/v1"
AUTH = ("Administrator", "Administrator")
PROJECTS_PATH = "/default-domain/workspaces/Projects"

def get_uid(path):
    try:
        r = requests.get(f"{NUXEO_URL}/path{path}", auth=AUTH)
        if r.status_code == 200:
            return r.json().get('uid')
    except:
        pass
    return None

def get_children(parent_uid):
    if not parent_uid:
        return []
    try:
        query = f"SELECT * FROM Document WHERE ecm:parentId = '{parent_uid}' AND ecm:isTrashed = 0"
        r = requests.get(f"{NUXEO_URL}/search/lang/NXQL/execute", params={'query': query}, auth=AUTH)
        if r.status_code == 200:
            return r.json().get('entries', [])
    except:
        pass
    return []

def main():
    projects_uid = get_uid(PROJECTS_PATH)
    
    # Initialize result structure
    result = {
        "projects_exists": bool(projects_uid),
        "structure": {},
        "root_docs": [],
        "initial_uids": {}
    }
    
    # Load initial UIDs
    if os.path.exists('/tmp/initial_doc_uids.json'):
        with open('/tmp/initial_doc_uids.json', 'r') as f:
            result['initial_uids'] = json.load(f)

    if projects_uid:
        children = get_children(projects_uid)
        
        # Analyze root children
        for child in children:
            doc_type = child.get('type')
            title = child.get('title')
            uid = child.get('uid')
            
            if doc_type == 'Folder':
                # Check contents of folders (Financial Reports, Proposals)
                folder_content = []
                sub_children = get_children(uid)
                for sub in sub_children:
                    folder_content.append({
                        "title": sub.get('title'),
                        "uid": sub.get('uid'),
                        "type": sub.get('type')
                    })
                
                result['structure'][title] = {
                    "uid": uid,
                    "children": folder_content,
                    "created_at": child.get('properties', {}).get('dc:created') 
                }
            else:
                # Document at root
                result['root_docs'].append({
                    "title": title,
                    "uid": uid,
                    "type": doc_type
                })

    # Add timestamp info
    result['task_start'] = int(os.environ.get('TASK_START', 0))
    result['task_end'] = int(os.environ.get('TASK_END', 0))
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == "__main__":
    main()
PYEOF

# Run the python script with environment variables
export TASK_START
export TASK_END
python3 /tmp/gather_nuxeo_state.py

# Ensure permissions on result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="