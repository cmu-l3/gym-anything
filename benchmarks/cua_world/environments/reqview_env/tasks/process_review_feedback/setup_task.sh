#!/bin/bash
set -e
echo "=== Setting up Process Review Feedback task ==="

source /workspace/scripts/task_utils.sh

# 1. Cleanup and Project Setup
pkill -f "reqview" 2>/dev/null || true
sleep 2

PROJECT_PATH=$(setup_task_project "review_feedback")
echo "Task project path: $PROJECT_PATH"

# 2. Python Script to Inject Comments
# We create this script on the fly to ensure specific requirements have comments
cat > /tmp/inject_comments.py << 'PYEOF'
import json
import os
import sys

def find_srs(project_dir):
    # Standard location in uncompressed project
    srs = os.path.join(project_dir, "documents", "SRS.json")
    if os.path.exists(srs):
        return srs
    return None

def inject_comments(srs_path):
    try:
        with open(srs_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading SRS: {e}")
        return

    # Map of ID suffix -> Comment Data
    targets = {
        "15": {
            "author": "Chief Engineer",
            "msg": "Performance Issue: The 200 ms timeout is too aggressive for legacy hardware. Please increase this to 500 ms.",
            "original_text_check": "200 ms" # Verification that we found the right node
        },
        "22": {
            "author": "Compliance Officer",
            "msg": "RFC 2119 Compliance: This requirement uses 'must'. Please change it to 'shall' to denote a binding requirement.",
            "original_text_check": "must"
        },
        "42": {
            "author": "Security Lead",
            "msg": "Ambiguity: 'Encryption' is too vague. We have standardized on AES-256. Please explicitly specify 'AES-256 algorithm'.",
            "original_text_check": "encryption" # lowercase check
        }
    }

    injected_count = 0

    def process_nodes(nodes):
        nonlocal injected_count
        for node in nodes:
            # Check ID
            nid = str(node.get('id', ''))
            
            # Simple check: if ID ends with our target number (e.g. "SRS-15" or just "15")
            for target_suffix, info in targets.items():
                if nid == target_suffix or nid.endswith("-" + target_suffix):
                    # verify text match to ensure we are editing the right thing (optional safety)
                    node_text = node.get('text', '').lower()
                    
                    # Add comment
                    discussion = node.get('discussion', [])
                    comment = {
                        "author": info['author'],
                        "date": "2023-10-27T10:00:00.000Z",
                        "message": info['msg']
                    }
                    discussion.append(comment)
                    node['discussion'] = discussion
                    print(f"Injected comment on SRS-{nid}")
                    injected_count += 1
            
            if 'children' in node:
                process_nodes(node['children'])

    if 'data' in data:
        process_nodes(data['data'])
    elif 'children' in data: # Some versions might use root children
        process_nodes(data['children'])
    else:
        # Array at root
        process_nodes(data)

    with open(srs_path, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Total comments injected: {injected_count}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python inject_comments.py <project_dir>")
        sys.exit(1)
    
    srs_file = find_srs(sys.argv[1])
    if srs_file:
        inject_comments(srs_file)
    else:
        print("SRS.json not found")
PYEOF

# 3. Run Injection
python3 /tmp/inject_comments.py "$PROJECT_PATH"

# 4. Record Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Application
launch_reqview_with_project "$PROJECT_PATH"

# 6. Setup UI State
sleep 5
dismiss_dialogs
maximize_window
open_srs_document

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="