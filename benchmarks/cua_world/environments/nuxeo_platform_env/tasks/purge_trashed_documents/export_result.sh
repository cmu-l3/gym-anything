#!/bin/bash
# Export script for purge_trashed_documents
# Checks the existence and state of the documents via REST API
# and saves the result to /tmp/task_result.json

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Load UIDs from setup
if [ ! -f /tmp/task_doc_uids.json ]; then
    echo "ERROR: UID file not found!"
    exit 1
fi

UID_ANDERSON=$(jq -r .purge.Anderson /tmp/task_doc_uids.json)
UID_BAKER=$(jq -r .purge.Baker /tmp/task_doc_uids.json)
UID_CHEN=$(jq -r .purge.Chen /tmp/task_doc_uids.json)
UID_DAVIS=$(jq -r .preserve.Davis /tmp/task_doc_uids.json)
UID_EVANS=$(jq -r .preserve.Evans /tmp/task_doc_uids.json)

# Function to check doc status
# Returns: "404" (Gone), "200_TRASHED" (Exists+Trashed), "200_ALIVE" (Exists+NotTrashed), or other code
check_doc_status() {
    local uid="$1"
    local response=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$uid")
    
    # Check if 404
    if echo "$response" | grep -q "\"status\":\s*404"; then
        echo "404"
        return
    fi
    if echo "$response" | grep -q "\"message\":\s*\"Request path not found\""; then
        echo "404"
        return
    fi
    
    # Check isTrashed property
    local is_trashed=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('isTrashed', 'False'))" 2>/dev/null)
    
    if [ "$is_trashed" == "True" ] || [ "$is_trashed" == "true" ]; then
        echo "200_TRASHED"
    else
        echo "200_ALIVE"
    fi
}

echo "Checking document statuses..."
STATUS_ANDERSON=$(check_doc_status "$UID_ANDERSON")
STATUS_BAKER=$(check_doc_status "$UID_BAKER")
STATUS_CHEN=$(check_doc_status "$UID_CHEN")
STATUS_DAVIS=$(check_doc_status "$UID_DAVIS")
STATUS_EVANS=$(check_doc_status "$UID_EVANS")

# Check Workspace existence
WS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/ClientRecords")

# Check Trash Count via NXQL
# Should be 2 (Davis and Evans)
TRASH_COUNT=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Document+WHERE+ecm:path+STARTSWITH+'/default-domain/workspaces/ClientRecords'+AND+ecm:isTrashed=1" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('resultsCount', -1))")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate JSON result
cat <<EOF > /tmp/task_result.json
{
  "status_anderson": "$STATUS_ANDERSON",
  "status_baker": "$STATUS_BAKER",
  "status_chen": "$STATUS_CHEN",
  "status_davis": "$STATUS_DAVIS",
  "status_evans": "$STATUS_EVANS",
  "workspace_http_code": "$WS_CODE",
  "trash_count": $TRASH_COUNT,
  "timestamp": $(date +%s)
}
EOF

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
chmod 666 /tmp/task_result.json