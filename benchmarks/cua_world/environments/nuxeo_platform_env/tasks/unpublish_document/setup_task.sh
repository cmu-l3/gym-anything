#!/bin/bash
# Setup for unpublish_document task
# Creates a workspace, a section, a document, and publishes the document to the section.

set -e
echo "=== Setting up unpublish_document task ==="

source /workspace/scripts/task_utils.sh

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 1. Create 'HR-Internal' Workspace
echo "Creating HR-Internal workspace..."
if ! doc_exists "/default-domain/workspaces/HR-Internal"; then
    create_doc "/default-domain/workspaces" "Workspace" "HR-Internal" \
        "HR Internal" "Private workspace for HR drafts" > /dev/null
fi

# 2. Create 'Employee-Portal' Section
echo "Creating Employee-Portal section..."
# Ensure Sections root exists (it usually does, but standard path is /default-domain/sections)
if ! doc_exists "/default-domain/sections/Employee-Portal"; then
    create_doc "/default-domain/sections" "Section" "Employee-Portal" \
        "Employee Portal" "Public documents for all employees" > /dev/null
fi
# Get Section ID for publishing
SECTION_JSON=$(nuxeo_api GET "/path/default-domain/sections/Employee-Portal")
SECTION_ID=$(echo "$SECTION_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

# 3. Create 'HR-Policy-2024-Draft' File in Workspace
echo "Creating HR Policy document..."
# We use a real PDF from the environment data
PDF_SOURCE="/workspace/data/quarterly_report.pdf" # Fallback if specific file missing
if [ -f "/workspace/data/project_proposal.pdf" ]; then
    PDF_SOURCE="/workspace/data/project_proposal.pdf"
fi

# Upload the file blob first
BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: HR_Policy_Draft.pdf" \
    --data-binary @"$PDF_SOURCE" > /dev/null

# Create the document with the blob
PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "HR-Policy-2024-Draft",
  "properties": {
    "dc:title": "HR Policy 2024 Draft",
    "dc:description": "Confidential draft of new policies.",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)

# Check if it exists, if not create it
if ! doc_exists "/default-domain/workspaces/HR-Internal/HR-Policy-2024-Draft"; then
    DOC_JSON=$(nuxeo_api POST "/path/default-domain/workspaces/HR-Internal/" "$PAYLOAD")
    DOC_ID=$(echo "$DOC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
else
    # Get ID of existing doc
    DOC_JSON=$(nuxeo_api GET "/path/default-domain/workspaces/HR-Internal/HR-Policy-2024-Draft")
    DOC_ID=$(echo "$DOC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
fi

# 4. Publish the document to the Section
echo "Publishing document to section..."
# Operation: Document.PublishToSection
# Params: target = section GUID
PUBLISH_PAYLOAD=$(printf '{"params":{"target":"%s"}}' "$SECTION_ID")
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/id/$DOC_ID/@op/Document.PublishToSection" \
    -d "$PUBLISH_PAYLOAD" > /dev/null

echo "Document published."

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
# Save IDs for verification
echo "$DOC_ID" > /tmp/original_doc_id.txt
echo "$SECTION_ID" > /tmp/section_id.txt

# 6. Prepare Browser
# Open Nuxeo Home. We do NOT navigate directly to the section; let the agent find it.
echo "Launching browser..."
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/sections" 8

# Ensure login
sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="