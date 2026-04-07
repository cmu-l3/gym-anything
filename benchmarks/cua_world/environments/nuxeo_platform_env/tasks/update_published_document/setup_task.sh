#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: update_published_document@1 ==="

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo
wait_for_nuxeo 180

# 3. Define Paths
WORKSPACE_PATH="/default-domain/workspaces/HR-Workspace"
SECTION_PATH="/default-domain/sections/HR-Intranet"
DOC_NAME="Remote-Work-Policy"
DOC_TITLE="Remote Work Policy"

# 4. Clean State (Delete if exists)
# Check Section
if doc_exists "$SECTION_PATH"; then
    echo "Section exists, cleaning content..."
    # We can't easily delete children via one API call, so we'll just recreate the section if needed
    # Or just assume clean env. Let's try to delete the specific document if it exists there.
    # Nuxeo proxies usually have the same name.
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$SECTION_PATH/$DOC_NAME" >/dev/null 2>&1 || true
else
    echo "Creating HR-Intranet section..."
    create_doc_if_missing "/default-domain/sections" "Section" "HR-Intranet" "HR Intranet" "Public HR documents"
fi

# Check Workspace
if doc_exists "$WORKSPACE_PATH"; then
    echo "Workspace exists."
    # Delete the doc to start fresh
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$WORKSPACE_PATH/$DOC_NAME" >/dev/null 2>&1 || true
else
    echo "Creating HR-Workspace..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "HR-Workspace" "HR Workspace" "Private HR working area"
fi

# Get Section UID for publishing
SECTION_UID=$(nuxeo_api GET "/path$SECTION_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

# 5. Create Document & Lifecycle (The Core Setup)
echo "Setting up document lifecycle..."

# Step A: Upload File & Create Doc (Version 0.0/0.1)
BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

# Use a real PDF (contract template serves as a policy doc)
PDF_SOURCE="/workspace/data/quarterly_report.pdf" # Fallback
[ -f "/home/ga/nuxeo/data/Contract_Template.pdf" ] && PDF_SOURCE="/home/ga/nuxeo/data/Contract_Template.pdf"

FILESIZE=$(stat -c%s "$PDF_SOURCE")
curl -s -u "$NUXEO_AUTH" \
    -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: RemoteWorkPolicy.pdf" \
    -H "X-File-Type: application/pdf" \
    -H "X-File-Size: $FILESIZE" \
    --data-binary @"$PDF_SOURCE" > /dev/null

PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "$DOC_NAME",
  "properties": {
    "dc:title": "$DOC_TITLE",
    "dc:description": "Policy for remote work (2023 Edition)",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)
# Create
DOC_RESP=$(nuxeo_api POST "/path$WORKSPACE_PATH/" "$PAYLOAD")
DOC_UID=$(echo "$DOC_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
echo "Created doc $DOC_UID"

# Step B: Check In as Version 1.0 (Major)
echo "Checking in v1.0..."
nuxeo_api POST "/id/$DOC_UID/@op/Document.CheckIn" '{"version": "major", "comment": "Initial 2023 Release"}' > /dev/null

# Step C: Publish v1.0 to Section
echo "Publishing v1.0 to HR-Intranet..."
nuxeo_api POST "/id/$DOC_UID/@op/Document.PublishToSection" "{\"target\": \"$SECTION_UID\"}" > /dev/null

# Step D: Update to Version 2.0 (The Twist)
echo "Updating document to v2.0..."
# Checkout (create working copy)
nuxeo_api POST "/id/$DOC_UID/@op/Document.CheckOut" > /dev/null

# Update Metadata
UPDATE_PAYLOAD='{"entity-type":"document","properties":{"dc:description":"Policy for remote work (2024 Updated Edition) - APPROVED"}}'
nuxeo_api PUT "/id/$DOC_UID" "$UPDATE_PAYLOAD" > /dev/null

# Check In as Version 2.0 (Major)
nuxeo_api POST "/id/$DOC_UID/@op/Document.CheckIn" '{"version": "major", "comment": "2024 Guidelines Update"}' > /dev/null

# Checkout again (so it's ready for editing if user wants, but mostly so it shows as "Project" state)
# Note: In Nuxeo, the 'live' document in the workspace is what the user interacts with. 
# It currently holds the content of v2.0.
nuxeo_api POST "/id/$DOC_UID/@op/Document.CheckOut" > /dev/null

echo "Setup State: Workspace has v2.0+ (Live), Section has v1.0 (Proxy)."

# 6. Prepare Browser
# Open Nuxeo at the Workspace level so the user sees the document immediately
open_nuxeo_url "$NUXEO_UI/repo$WORKSPACE_PATH" 8
nuxeo_login

# 7. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="