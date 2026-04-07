#!/bin/bash
set -e
echo "=== Setting up merge_security_requirements task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup a fresh project copy
PROJECT_PATH=$(setup_task_project "merge_security")
echo "Task project path: $PROJECT_PATH"

# 3. Generate a content fingerprint for verification
# We pick a unique string from the ASVS document to ensure it actually gets moved.
# We'll save this to a file that the verifier can read later.
python3 << PYEOF
import json
import sys
import os
import re

def strip_html(text):
    return re.sub(r'<[^>]+>', '', str(text)).strip()

asvs_path = "$PROJECT_PATH/documents/ASVS.json"
fingerprint_file = "/tmp/asvs_fingerprint.txt"

try:
    with open(asvs_path, 'r') as f:
        data = json.load(f)
    
    # Find the first real requirement to use as fingerprint
    # Structure: data['data'] is a list of objects (sections/reqs)
    
    fingerprint = ""
    
    def find_req_text(items):
        for item in items:
            text = strip_html(item.get('text', '') or item.get('description', ''))
            if text and len(text) > 20:
                return text
            if 'children' in item:
                found = find_req_text(item['children'])
                if found: return found
        return None

    fingerprint = find_req_text(data.get('data', []))
    
    if fingerprint:
        with open(fingerprint_file, 'w') as f:
            f.write(fingerprint)
        print(f"Generated fingerprint: {fingerprint[:50]}...")
    else:
        print("WARNING: Could not generate ASVS fingerprint (empty document?)")
        # Write a fallback or empty file so verifier doesn't crash on copy
        with open(fingerprint_file, 'w') as f:
            f.write("FALLBACK_FINGERPRINT_NOT_FOUND")

except Exception as e:
    print(f"ERROR generating fingerprint: {e}")
    # Write a fallback
    with open(fingerprint_file, 'w') as f:
        f.write("ERROR_GENERATING_FINGERPRINT")
PYEOF

# 4. Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"

# 5. UI Prep
dismiss_dialogs
maximize_window

# Open ASVS document initially so the agent sees the source material immediately
echo "Opening ASVS document..."
# Coordinates for ASVS in tree. Project tree items: INF, NEEDS, ASVS, RISKS...
# ASVS is roughly 3rd or 4th item.
# We'll click safely in the tree area.
# Actually, the task description says "Open ASVS", so we can leave it closed or open.
# Opening it helps the agent context.
# Assuming standard resolution 1920x1080 maximized:
# Tree is on left. ASVS might be around (100, 300) depending on expansion.
# We won't force-click a specific coordinate to avoid opening the wrong thing if tree state varies.
# Instead, we rely on the agent to find it. But we will make sure the window is ready.

take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="