#!/bin/bash
echo "=== Exporting rename_case_document results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read context
CASE_ID=$(jq -r '.caseId' /tmp/task_context.json 2>/dev/null || echo "")
DOC_ID=$(jq -r '.documentId' /tmp/task_context.json 2>/dev/null || echo "")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: No Case ID found in context. Cannot verify API state."
    # Create empty result
    cat > /tmp/task_result.json << EOF
{
    "error": "Setup failed or context lost",
    "case_found": false
}
EOF
    exit 0
fi

# Query ArkCase API for current document state
cat > /tmp/check_result.py << PYEOF
import requests
import json
import sys

BASE_URL = "https://localhost:9443/arkcase/api/v1"
AUTH = ("arkcase-admin@dev.arkcase.com", "ArkCase1234!")
VERIFY_SSL = False
CASE_ID = "$CASE_ID"
TARGET_DOC_ID = "$DOC_ID"

def get_case_documents():
    # Attempt to list documents for the case
    # Endpoint might be /plugin/complaint/{id}/documents or similar
    url = f"{BASE_URL}/plugin/complaint/{CASE_ID}/documents"
    
    try:
        resp = requests.get(url, auth=AUTH, verify=VERIFY_SSL)
        # If specific endpoint fails, try generic search or dms container
        if resp.status_code != 200:
             # Try /dms/container/{id}/children
             url = f"{BASE_URL}/dms/container/{CASE_ID}/children"
             resp = requests.get(url, auth=AUTH, verify=VERIFY_SSL)
        
        if resp.status_code == 200:
            return resp.json()
        return []
    except Exception as e:
        print(f"API Error: {e}", file=sys.stderr)
        return []

docs = get_case_documents()
found_doc = None
doc_count = len(docs)

# Find our target document
for d in docs:
    # Match by ID if possible, otherwise look for the new name
    did = d.get("documentId") or d.get("id") or d.get("objectId")
    if str(did) == str(TARGET_DOC_ID):
        found_doc = d
        break

# If ID matching is tricky (some APIs return different ref IDs), check by name match as fallback
if not found_doc:
    for d in docs:
        dname = d.get("documentName", "") or d.get("title", "") or d.get("name", "")
        if "Response_Letter" in dname:
            found_doc = d
            break

result = {
    "case_id": CASE_ID,
    "doc_count": doc_count,
    "doc_found": found_doc is not None,
    "document": found_doc if found_doc else {},
    "task_start": $TASK_START,
    "task_end": $TASK_END
}

print(json.dumps(result))
PYEOF

echo "Querying API for result..."
python3 /tmp/check_result.py > /tmp/api_result.json 2>/dev/null

# Merge with simple file info
cat > /tmp/merge_results.py << PYEOF
import json
import os

try:
    with open("/tmp/api_result.json", "r") as f:
        api_data = json.load(f)
except:
    api_data = {}

result = {
    "api_data": api_data,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

python3 /tmp/merge_results.py

# Clean up permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="