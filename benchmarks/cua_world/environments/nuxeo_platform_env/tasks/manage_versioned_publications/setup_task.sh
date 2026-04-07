#!/bin/bash
# Setup for manage_versioned_publications
# 1. Creates Sections (Customer Portal, Engineering Internal)
# 2. Creates Source Document (Titanium X Specs) with V1 content
# 3. Stages V2 content file for agent to use
# 4. Opens Firefox to source document

set -e
echo "=== Setting up manage_versioned_publications task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo availability
wait_for_nuxeo 120

echo "Configuring Nuxeo structure..."

# 1. Ensure Sections exist
# Create 'Customer-Portal'
if ! doc_exists "/default-domain/sections/Customer-Portal"; then
    create_doc_if_missing "/default-domain/sections" "Section" "Customer-Portal" \
        "Customer Portal" "Public-facing documentation area"
fi

# Create 'Engineering-Internal'
if ! doc_exists "/default-domain/sections/Engineering-Internal"; then
    create_doc_if_missing "/default-domain/sections" "Section" "Engineering-Internal" \
        "Engineering Internal" "Internal technical specifications"
fi

# 2. Prepare Source Document in Projects workspace
# Ensure Projects workspace exists
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" ""

# Check if source doc exists, delete if it does to ensure clean state (fresh version history)
if doc_exists "/default-domain/workspaces/Projects/Titanium-X-Specs"; then
    echo "Resetting source document..."
    # Get UID to delete
    UID_TO_DEL=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Titanium-X-Specs" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
    if [ -n "$UID_TO_DEL" ]; then
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$UID_TO_DEL" > /dev/null
    fi
    sleep 2
fi

# Upload "Public" content (Annual Report renamed) to create the source doc
PUBLIC_PDF="/workspace/data/annual_report_2023.pdf"
# Fallback if not mounted
[ ! -f "$PUBLIC_PDF" ] && PUBLIC_PDF="/home/ga/nuxeo/data/Annual_Report_2023.pdf"

echo "Creating source document 'Titanium-X-Specs'..."
# Upload batch
BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "X-File-Name: Titanium_X_Specs.pdf" \
    -H "X-File-Type: application/pdf" \
    --data-binary @"$PUBLIC_PDF" > /dev/null

# Create Document
PAYLOAD='{
  "entity-type": "document",
  "type": "File",
  "name": "Titanium-X-Specs",
  "properties": {
    "dc:title": "Titanium X Specs",
    "dc:description": "Official product specifications",
    "file:content": {
      "upload-batch": "'"$BATCH_ID"'",
      "upload-fileId": "0"
    }
  }
}'
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects" \
    -d "$PAYLOAD" > /dev/null

echo "Source document created."

# 3. Stage the "Internal" draft file for the agent
INTERNAL_PDF_SRC="/workspace/data/project_proposal.pdf"
[ ! -f "$INTERNAL_PDF_SRC" ] && INTERNAL_PDF_SRC="/home/ga/nuxeo/data/Project_Proposal.pdf"

STAGED_FILE="/home/ga/nuxeo/data/Titanium_X_Internal_Draft.pdf"
mkdir -p "$(dirname "$STAGED_FILE")"
cp "$INTERNAL_PDF_SRC" "$STAGED_FILE"
chown ga:ga "$STAGED_FILE"

echo "Internal draft file staged at: $STAGED_FILE"

# 4. Open Firefox to the source document
TARGET_URL="$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Titanium-X-Specs"
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login logic (reused from utils)
# Ensure we are on login page
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to specific document
navigate_to "$TARGET_URL"

# Record initial state digest for verification
INITIAL_DIGEST=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Titanium-X-Specs" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('file:content',{}).get('digest',''))")
echo "$INITIAL_DIGEST" > /tmp/initial_digest.txt

# Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="