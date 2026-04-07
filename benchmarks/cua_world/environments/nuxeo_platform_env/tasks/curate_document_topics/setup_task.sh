#!/bin/bash
# Pre-task setup for curate_document_topics
# Creates specific documents with incorrect metadata state and ensures vocabulary exists.

set -e
echo "=== Setting up curate_document_topics task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# 1. Ensure 'Projects' workspace exists
# ---------------------------------------------------------------------------
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Active project documents"

# ---------------------------------------------------------------------------
# 2. Ensure Vocabulary Entries Exist (Art, Sciences)
# ---------------------------------------------------------------------------
# The UI subject picker relies on the 'l10nsubjects' directory.
# We ensure the IDs 'art' and 'sciences' exist.

ensure_vocab_entry() {
    local id="$1"
    local label="$2"
    # Check if entry exists
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/directory/l10nsubjects/$id")
    
    if [ "$HTTP_CODE" != "200" ]; then
        echo "Creating vocabulary entry '$label' ($id)..."
        payload=$(printf '{"entity-type":"directoryEntry","directoryName":"l10nsubjects","properties":{"id":"%s","label":"%s","obsolete":0,"ordering":10000000}}' "$id" "$label")
        nuxeo_api POST "/directory/l10nsubjects" "$payload" > /dev/null
    else
        echo "Vocabulary entry '$label' ($id) already exists."
    fi
}

echo "Verifying taxonomy vocabulary..."
ensure_vocab_entry "art" "Art"
ensure_vocab_entry "sciences" "Sciences"

# ---------------------------------------------------------------------------
# 3. Create 'Project Specifications' with INCORRECT subject (Art)
# ---------------------------------------------------------------------------
echo "Preparing 'Project Specifications'..."

# Remove if exists to ensure clean state
if doc_exists "/default-domain/workspaces/Projects/Project-Specifications"; then
    nuxeo_api DELETE "/path/default-domain/workspaces/Projects/Project-Specifications" > /dev/null
fi

# Upload a PDF
PDF_SOURCE="/workspace/data/project_proposal.pdf"
if [ ! -f "$PDF_SOURCE" ]; then PDF_SOURCE="/workspace/data/sample.pdf"; fi
# Fallback if no PDF exists
if [ ! -f "$PDF_SOURCE" ]; then
    echo "Dummy PDF content" > /tmp/dummy.pdf
    PDF_SOURCE="/tmp/dummy.pdf"
fi

BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Project_Specs.pdf" \
    --data-binary @"$PDF_SOURCE" > /dev/null

# Create doc with 'art' subject (INCORRECT)
PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Project-Specifications",
  "properties": {
    "dc:title": "Project Specifications",
    "dc:description": "Technical specifications for the new initiative.",
    "dc:subjects": ["art"],
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
nuxeo_api POST "/path/default-domain/workspaces/Projects" "$PAYLOAD" > /dev/null
echo "Created 'Project Specifications' with subject: Art"

# ---------------------------------------------------------------------------
# 4. Create 'Gallery Brochure' with NO subjects
# ---------------------------------------------------------------------------
echo "Preparing 'Gallery Brochure'..."

if doc_exists "/default-domain/workspaces/Projects/Gallery-Brochure"; then
    nuxeo_api DELETE "/path/default-domain/workspaces/Projects/Gallery-Brochure" > /dev/null
fi

# Reuse PDF source
BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: brochure.pdf" \
    --data-binary @"$PDF_SOURCE" > /dev/null

PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Gallery-Brochure",
  "properties": {
    "dc:title": "Gallery Brochure",
    "dc:description": "Brochure for the upcoming exhibit.",
    "dc:subjects": [],
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
nuxeo_api POST "/path/default-domain/workspaces/Projects" "$PAYLOAD" > /dev/null
echo "Created 'Gallery Brochure' with no subjects."

# ---------------------------------------------------------------------------
# 5. Launch Browser
# ---------------------------------------------------------------------------
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Ensure window is titled correctly for login check
sleep 2
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")

# Login
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# ---------------------------------------------------------------------------
# 6. Initial Screenshot
# ---------------------------------------------------------------------------
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="