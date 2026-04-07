#!/bin/bash
echo "=== Exporting update_collection_content results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if Firefox is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 3. Use Python to query Nuxeo API and export structured JSON result
# We do this here so the verification logic is self-contained in the export
# and avoids 'exec_in_env' issues in the verifier.
cat << 'EOF' | python3 > /tmp/task_result.json
import requests
import json
import time

NUXEO_URL = "http://localhost:8080/nuxeo/api/v1"
AUTH = ("Administrator", "Administrator")
HEADERS = {"Content-Type": "application/json"}

result = {
    "collection_found": False,
    "description": "",
    "members": [],
    "error": None
}

try:
    # 1. Get Collection Details (using path we set up)
    # Note: If agent moved it, we might fail, but that's part of the task (don't move it)
    col_path = "/default-domain/workspaces/Projects/Brand-Assets"
    r = requests.get(f"{NUXEO_URL}/path{col_path}", auth=AUTH, headers=HEADERS)
    
    if r.status_code == 200:
        data = r.json()
        result["collection_found"] = True
        result["description"] = data.get("properties", {}).get("dc:description", "")
        col_uid = data.get("uid")

        # 2. Get Collection Members
        # Query: documents that are members of this collection
        query = f"SELECT * FROM Document WHERE collectionMember:collectionIds = '{col_uid}' AND ecm:isTrashed = 0"
        r_members = requests.get(f"{NUXEO_URL}/search/lang/NXQL/execute", 
                               auth=AUTH, headers=HEADERS, params={"query": query})
        
        if r_members.status_code == 200:
            entries = r_members.json().get("entries", [])
            # Store just the titles for verification
            result["members"] = [e.get("title") for e in entries]
    else:
        result["error"] = f"Collection not found at expected path (Status {r.status_code})"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# 4. Add timestamp info to the result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge JSONs using jq (available in env) or simple python append
# Using python to be safe if jq isn't standard in all base images
python3 -c "
import json
import sys

try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['app_running'] = '$APP_RUNNING'.lower() == 'true'

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="