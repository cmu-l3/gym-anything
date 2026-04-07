#!/bin/bash
# pre_task hook for deduplicate_project_files
# Creates a Finance workspace and two duplicate documents with different timestamps.

echo "=== Setting up deduplicate_project_files task ==="

source /workspace/scripts/task_utils.sh

# Wait for Nuxeo to be fully up
wait_for_nuxeo 180

# 1. Create Finance Workspace
echo "Creating Finance workspace..."
# Delete if exists to ensure clean state
if doc_exists "/default-domain/workspaces/Finance"; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Finance"
    sleep 2
fi

# Create workspace
WS_RESP=$(nuxeo_api POST "/path/default-domain/workspaces" '{"entity-type":"document","type":"Workspace","name":"Finance","properties":{"dc:title":"Finance","dc:description":"Financial reports and audits"}}')
WS_UID=$(echo "$WS_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "Created Finance workspace (UID: $WS_UID)"

# 2. Prepare content file
PDF_SOURCE="/workspace/data/quarterly_report.pdf"
if [ ! -f "$PDF_SOURCE" ]; then
    PDF_SOURCE="/home/ga/nuxeo/data/Contract_Template.pdf" # Fallback
fi

# Function to upload file and create document
create_file_doc() {
    local title="$1"
    local desc="$2"
    
    # Upload blob
    local batch_resp=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    local batch_id=$(echo "$batch_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$batch_id/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: report.pdf" \
        -H "X-File-Type: application/pdf" \
        --data-binary @"$PDF_SOURCE" > /dev/null

    # Create Document
    local payload=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Q3-Financials",
  "properties": {
    "dc:title": "$title",
    "dc:description": "$desc",
    "file:content": {
      "upload-batch": "$batch_id",
      "upload-fileId": "0"
    }
  }
}
EOF
)
    # Nuxeo handles name collisions by appending numbers if name exists, or we can let it handle it.
    # However, to ensure they look identical in title, we set dc:title same.
    # We post to the workspace path.
    local resp=$(nuxeo_api POST "/path/default-domain/workspaces/Finance" "$payload")
    echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))"
}

# 3. Create OLDER document
echo "Creating Older document..."
OLDER_UID=$(create_file_doc "Q3 Financials" "Preliminary Q3 Report (Older)")
echo "Older Doc UID: $OLDER_UID"

# 4. Wait to ensure timestamp difference (at least 2 seconds for clear UI distinction)
echo "Waiting to create timestamp gap..."
sleep 5

# 5. Create NEWER document
echo "Creating Newer document..."
NEWER_UID=$(create_file_doc "Q3 Financials" "Final Q3 Report (Newer)")
echo "Newer Doc UID: $NEWER_UID"

# 6. Record Ground Truth for verification
cat > /tmp/task_ground_truth.json <<EOF
{
  "older_uid": "$OLDER_UID",
  "newer_uid": "$NEWER_UID",
  "workspace_uid": "$WS_UID",
  "setup_timestamp": $(date +%s)
}
EOF
chmod 644 /tmp/task_ground_truth.json
echo "Ground truth saved."

# 7. Set up Browser
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Login if needed
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to Finance workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Finance"

echo "=== Setup complete ==="