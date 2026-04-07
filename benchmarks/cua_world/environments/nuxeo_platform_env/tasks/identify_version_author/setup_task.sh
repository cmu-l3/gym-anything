#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Identify Version Author ==="

# 1. Define variables
TARGET_USER="arch_lead"
TARGET_PASS="password123"
DOC_NAME="System_Architecture.pdf"
WORKSPACE_PATH="/default-domain/workspaces/Projects"
DOC_PATH="$WORKSPACE_PATH/System-Architecture"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Save ground truth for local verification scripts if needed (verifier.py uses task.json metadata)
echo "$TARGET_USER" > /tmp/ground_truth_user.txt

# 2. Ensure Nuxeo is ready
wait_for_nuxeo 180

# 3. Create the target user (the architect)
# Check if user exists first to avoid errors on retry
USER_CHECK=$(curl -s -u "$NUXEO_AUTH" -o /dev/null -w "%{http_code}" "$NUXEO_URL/api/v1/user/$TARGET_USER")
if [ "$USER_CHECK" != "200" ]; then
    echo "Creating user $TARGET_USER..."
    USER_PAYLOAD=$(cat <<EOF
{
  "entity-type": "user",
  "id": "$TARGET_USER",
  "properties": {
    "username": "$TARGET_USER",
    "firstName": "Senior",
    "lastName": "Architect",
    "email": "architect@example.com",
    "password": "$TARGET_PASS",
    "groups": ["members"]
  }
}
EOF
)
    nuxeo_api POST "/user" "$USER_PAYLOAD" > /dev/null
    echo "User $TARGET_USER created."
fi

# 4. Create the document AS ADMINISTRATOR (Initial Creator)
# This ensures dc:creator is Administrator, distinct from our target.
echo "Creating initial document as Administrator..."

# Check if doc exists and delete it to ensure clean history
if doc_exists "$DOC_PATH"; then
    echo "Document exists, deleting to reset history..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$DOC_PATH" > /dev/null
    sleep 2
fi

# Upload a real PDF to use as content
PDF_SOURCE="/workspace/data/annual_report_2023.pdf"
if [ ! -f "$PDF_SOURCE" ]; then
    # Fallback if real data missing
    echo "Creating dummy PDF..."
    PDF_SOURCE="/tmp/dummy.pdf"
    echo "Dummy PDF content" > "$PDF_SOURCE"
fi

# Upload blob
BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: $DOC_NAME" \
    --data-binary @"$PDF_SOURCE" > /dev/null

# Create Document
DOC_PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "System-Architecture",
  "properties": {
    "dc:title": "System_Architecture.pdf",
    "dc:description": "Core system architecture specifications. Initial draft.",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)
nuxeo_api POST "/path$WORKSPACE_PATH" "$DOC_PAYLOAD" > /dev/null
echo "Document created."

# 5. Grant Write permission to the target user (so they can create a version)
echo "Granting Write permission to $TARGET_USER..."
PERM_PAYLOAD='{"params": {"permission": "ReadWrite", "username": "'"$TARGET_USER"'"}}'
nuxeo_api POST "/path$DOC_PATH/@op/Document.AddPermission" "$PERM_PAYLOAD" > /dev/null

# 6. Perform edits AS TARGET USER and create VERSION 1.0
echo "Simulating edits by $TARGET_USER..."

# Update properties to "dirty" the document
UPDATE_PAYLOAD='{"entity-type":"document","properties":{"dc:description":"Architecture finalized for v1.0 release."}}'
curl -s -u "$TARGET_USER:$TARGET_PASS" \
    -H "Content-Type: application/json" \
    -H "X-NXproperties: *" \
    -X PUT \
    "$NUXEO_URL/api/v1/path$DOC_PATH" \
    -d "$UPDATE_PAYLOAD" > /dev/null

# Check in as Version 1.0 (Major Version)
VERSION_PAYLOAD='{"params": {"increment": "Major"}}'
curl -s -u "$TARGET_USER:$TARGET_PASS" \
    -H "Content-Type: application/json" \
    -X POST \
    "$NUXEO_URL/api/v1/path$DOC_PATH/@op/Document.CreateVersion" \
    -d "$VERSION_PAYLOAD" > /dev/null

echo "Version 1.0 created by $TARGET_USER."

# 7. Perform edits AS ADMINISTRATOR (Create Version 1.1)
# This hides the target user from the "Last Contributor" field on the summary
echo "Updating document as Administrator (creating v1.1)..."
sleep 2
UPDATE_ADMIN_PAYLOAD='{"entity-type":"document","properties":{"dc:description":"Updated with post-release notes."}}'
nuxeo_api PUT "/path$DOC_PATH" "$UPDATE_ADMIN_PAYLOAD" > /dev/null

VERSION_ADMIN_PAYLOAD='{"params": {"increment": "Minor"}}'
nuxeo_api POST "/path$DOC_PATH/@op/Document.CreateVersion" "$VERSION_ADMIN_PAYLOAD" > /dev/null
echo "Version 1.1 created by Administrator."

# 8. Clean up local artifacts
rm -f /home/ga/version_author.txt 2>/dev/null

# 9. Launch Firefox
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Login
nuxeo_login

# Navigate to Projects workspace to start
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="