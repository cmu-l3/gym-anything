#!/bin/bash
# Export script for create_document_version task
# Queries Nuxeo API for final document state and history, then saves to JSON.

source /workspace/scripts/task_utils.sh

echo "=== Exporting create_document_version results ==="

DOC_PATH="/default-domain/workspaces/Projects/Annual-Report-2023"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Live Document State
echo "Fetching live document state..."
DOC_JSON=$(nuxeo_api GET "/path$DOC_PATH" 2>/dev/null)

# Extract UID for version query
DOC_UID=$(echo "$DOC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

# 3. Get Version History
VERSIONS_JSON="{}"
if [ -n "$DOC_UID" ]; then
    echo "Fetching version history for UID: $DOC_UID"
    # Query for all versions of this document
    QUERY="SELECT * FROM Document WHERE ecm:versionVersionableId = '$DOC_UID' AND ecm:isVersion = 1 ORDER BY dc:created DESC"
    ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote(\"$QUERY\"))")
    VERSIONS_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=$ENCODED_QUERY")
fi

# 4. Compile Result JSON
# We use Python to robustly construct the JSON to avoid escaping hell in bash
python3 -c "
import json
import os
import sys

try:
    doc_data = json.loads('''$DOC_JSON''')
    versions_data = json.loads('''$VERSIONS_JSON''')
except Exception as e:
    doc_data = {}
    versions_data = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'live_document': doc_data,
    'version_history': versions_data,
    'screenshot_path': '/tmp/task_final.png',
    'screenshot_exists': os.path.exists('/tmp/task_final.png')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can copy it (though usually root runs export)
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="