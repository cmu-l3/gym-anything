#!/bin/bash
# Export script for promote_personal_draft_to_shared_workspace

set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Retrieve original UUID
if [ -f /tmp/target_doc_uuid.txt ]; then
    TARGET_UUID=$(cat /tmp/target_doc_uuid.txt)
else
    echo "ERROR: Target UUID file not found."
    TARGET_UUID=""
fi

# 3. Query Nuxeo API for the document status
echo "Querying document status for UUID: $TARGET_UUID..."

DOC_STATUS_FILE="/tmp/doc_status.json"

if [ -n "$TARGET_UUID" ]; then
    # Get document details
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        "$NUXEO_URL/api/v1/id/$TARGET_UUID" > "$DOC_STATUS_FILE"
else
    echo "{}" > "$DOC_STATUS_FILE"
fi

# 4. Check if a NEW document was created with the target name (Anti-gaming check for copy/paste vs move)
# We search for the target title in the target path
TARGET_TITLE="Board_Meeting_Agenda_Oct2023"
SEARCH_RESULTS_FILE="/tmp/search_results.json"

QUERY="SELECT * FROM Document WHERE dc:title = '$TARGET_TITLE' AND ecm:path STARTSWITH '/default-domain/workspaces/Projects'"
curl -s -u "$NUXEO_AUTH" \
    -G \
    --data-urlencode "query=$QUERY" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute" > "$SEARCH_RESULTS_FILE"

# 5. Prepare final result JSON
# We combine the status of the original UUID doc and any search results
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to merge JSONs using python
python3 -c "
import json, os, sys

try:
    with open('/tmp/doc_status.json') as f:
        doc_status = json.load(f)
except:
    doc_status = {}

try:
    with open('/tmp/search_results.json') as f:
        search_results = json.load(f)
except:
    search_results = {}

result = {
    'original_doc_uuid': '$TARGET_UUID',
    'doc_status': doc_status,
    'search_results': search_results,
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
echo "=== Export Complete ==="