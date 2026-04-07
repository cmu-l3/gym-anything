#!/bin/bash
echo "=== Exporting generate_document_audit_report results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record task timing and file stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/audit_report.json"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. GENERATE GROUND TRUTH (Internal Verification Data)
# We query the Nuxeo API directly to get the TRUE audit history to compare against
echo "Generating ground truth data..."
GROUND_TRUTH_FILE="/tmp/ground_truth_audit.json"

# Python script to fetch all docs in Projects and their audit logs
cat << 'EOF' > /tmp/fetch_ground_truth.py
import requests
import json
import os

NUXEO_URL = "http://localhost:8080/nuxeo/api/v1"
AUTH = ("Administrator", "Administrator")
WORKSPACE = "/default-domain/workspaces/Projects"

def get_docs():
    query = f"SELECT * FROM Document WHERE ecm:path STARTSWITH '{WORKSPACE}' AND ecm:mixinType != 'HiddenInNavigation' AND ecm:isProxy = 0 AND ecm:isTrashed = 0"
    params = {'query': query, 'properties': 'dublincore'}
    resp = requests.get(f"{NUXEO_URL}/query", params=params, auth=AUTH)
    if resp.status_code != 200: return []
    return resp.json().get('entries', [])

def get_audit(doc_uid):
    resp = requests.get(f"{NUXEO_URL}/id/{doc_uid}/@audit", auth=AUTH)
    if resp.status_code != 200: return []
    return resp.json().get('entries', [])

data = {
    "docs_found": [],
    "audit_entries": []
}

docs = get_docs()
for doc in docs:
    uid = doc.get('uid')
    path = doc.get('path')
    title = doc.get('properties', {}).get('dc:title')
    data['docs_found'].append({"uid": uid, "path": path, "title": title})
    
    entries = get_audit(uid)
    for entry in entries:
        # Flatten relevant fields for comparison
        data['audit_entries'].append({
            "doc_uid": uid,
            "doc_path": path,
            "event_id": entry.get('eventId'),
            "event_date": entry.get('eventDate'),
            "principal": entry.get('principalName'),
            "category": entry.get('category')
        })

print(json.dumps(data))
EOF

python3 /tmp/fetch_ground_truth.py > "$GROUND_TRUTH_FILE" 2>/dev/null || echo "{}" > "$GROUND_TRUTH_FILE"

# 4. Create metadata export file
cat << EOF > /tmp/task_result.json
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "output_size": $FILE_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK
}
EOF

# 5. Move files to safe location for copy_from_env
# (The framework copies from /tmp usually or we specify paths in verifier)
# We will leave them in /tmp/ and /home/ga/ and access them via absolute paths in verifier.

echo "=== Export complete ==="