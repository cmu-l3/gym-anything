#!/bin/bash
# post_task hook for deduplicate_project_files
# Checks the state of the specific documents created in setup.

echo "=== Exporting deduplicate_project_files result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Load ground truth
if [ ! -f /tmp/task_ground_truth.json ]; then
    echo "ERROR: Ground truth file not found!"
    exit 1
fi

OLDER_UID=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json')).get('older_uid',''))")
NEWER_UID=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json')).get('newer_uid',''))")

echo "Verifying UIDs -> Older: $OLDER_UID, Newer: $NEWER_UID"

# Function to get doc status
get_doc_status() {
    local uid="$1"
    # fetch isTrashed state
    nuxeo_api GET "/id/$uid" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    is_trashed = data.get('isTrashed', False)
    title = data.get('title', 'Unknown')
    print(json.dumps({'exists': True, 'is_trashed': is_trashed, 'title': title}))
except:
    print(json.dumps({'exists': False, 'is_trashed': False, 'title': ''}))
"
}

OLDER_STATUS=$(get_doc_status "$OLDER_UID")
NEWER_STATUS=$(get_doc_status "$NEWER_UID")

# Check Workspace contents (active documents only)
# NXQL query for children of Finance that are NOT trashed
WS_CHILDREN_COUNT=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:parentId='$WS_UID'+AND+ecm:isTrashed=0" \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries',[])))")

# Create result JSON
RESULT_JSON="/tmp/task_result.json"
cat > "$RESULT_JSON" <<EOF
{
  "older_doc": $OLDER_STATUS,
  "newer_doc": $NEWER_STATUS,
  "active_children_count": $WS_CHILDREN_COUNT,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="