#!/bin/bash
# Setup script for promote_personal_draft_to_shared_workspace

set -e
echo "=== Setting up Promote Personal Draft task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure destination 'Projects' workspace exists
echo "Ensuring Projects workspace exists..."
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Shared project workspace" > /dev/null
fi

# 4. Initialize/Find Personal Workspace for Administrator
# We create a dummy doc to force initialization if needed, or just calculate the path.
# Standard path for Administrator in default domain
USER_WS_PATH="/default-domain/UserWorkspaces/Administrator"

# Try to create the UserWorkspaces root if it doesn't exist (sometimes needed on fresh installs)
if ! doc_exists "/default-domain/UserWorkspaces"; then
    # Usually created by system, but we can try just in case or assume it exists after login
    # Triggering a login usually creates it.
    echo "UserWorkspaces might need initialization..."
fi

# 5. Create the 'Draft_Agenda' document in Personal Workspace
# We use the REST API. If the path doesn't exist, we might need to rely on the "user workspace" API endpoint logic
# but sticking to direct path is easier if we know it.
# Let's try to upload a file to it.

echo "Creating Draft_Agenda in Personal Workspace..."

# Prepare a dummy PDF
DRAFT_PDF="/tmp/Draft_Agenda.pdf"
echo "Agenda Content - Draft Version" > /tmp/agenda.txt
# Convert text to simple PDF using imagemagick or just use the text file as a blob
# Using a real PDF from env if available, else make a dummy
if [ -f "/workspace/data/annual_report_2023.pdf" ]; then
    cp "/workspace/data/annual_report_2023.pdf" "$DRAFT_PDF"
else
    # Create minimal PDF
    printf "%%PDF-1.0\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 595 842]/Parent 2 0 R>>endobj xref 0 4 0000000000 65535 f 0000000010 00000 n 0000000060 00000 n 0000000117 00000 n trailer<</Size 4/Root 1 0 R>>\nstartxref\n185\n%%EOF\n" > "$DRAFT_PDF"
fi

# Upload blob
BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: Draft_Agenda.pdf" \
    -H "X-File-Type: application/pdf" \
    --data-binary @"$DRAFT_PDF" > /dev/null

# Create Document
# We try to create it at the standard path. If 404, we assume user workspace isn't init'd and creates it via user specific call?
# Nuxeo doesn't always have a strict path for user workspaces until created.
# Strategy: Use the 'path' endpoint for the user to ensure it exists.
# Getting user workspace path via API is tricky without specific endpoint, checking standard path:
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$USER_WS_PATH")

if [ "$HTTP_CODE" != "200" ]; then
    echo "Personal workspace not found at $USER_WS_PATH. Attempting to create UserWorkspaces root..."
    # This part is tricky. Usually we just need to login once.
    # We will assume the environment setup (post_start) did a login or we do one now.
fi

PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Draft_Agenda",
  "properties": {
    "dc:title": "Draft_Agenda",
    "dc:description": "Confidential draft for board meeting",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)

# Create the doc
RESPONSE=$(nuxeo_api POST "/path$USER_WS_PATH/" "$PAYLOAD")

# Extract UUID
DOC_UUID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

if [ -z "$DOC_UUID" ]; then
    echo "ERROR: Failed to create Draft_Agenda. API Response:"
    echo "$RESPONSE"
    # Fallback: Create in default domain root if personal workspace fails, though this changes the task slightly
    # Re-attempt in default-domain just to have a doc
    RESPONSE=$(nuxeo_api POST "/path/default-domain/" "$PAYLOAD")
    DOC_UUID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
    echo "Created in fallback location /default-domain/"
fi

echo "Created Draft_Agenda with UUID: $DOC_UUID"
echo "$DOC_UUID" > /tmp/target_doc_uuid.txt

# 6. Launch Firefox and navigate to Personal Workspace
# We navigate to the user's personal workspace URL
PERSONAL_WS_URL="$NUXEO_UI/#!/browse$USER_WS_PATH"

echo "Opening Firefox..."
# Ensure any previous instance is killed
pkill -9 -f firefox || true
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login
nuxeo_login

# Navigate to Personal Workspace
navigate_to "$PERSONAL_WS_URL"

# Take setup screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="