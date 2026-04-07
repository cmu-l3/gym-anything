#!/bin/bash
set -e
echo "=== Setting up update_collection_content task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 300

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create initial documents in 'Projects' workspace
echo "Creating source documents..."
# Ensure Projects workspace exists
create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Workspace for active projects"

# Create Obsolete Logo (File)
if ! doc_exists "/default-domain/workspaces/Projects/Obsolete-Logo"; then
    BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    # Upload dummy content
    echo "Old Logo Content" > /tmp/obsolete.txt
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: obsolete_logo.txt" \
        -d "Dummy Content" > /dev/null
        
    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Obsolete-Logo",
  "properties": {
    "dc:title": "Obsolete-Logo",
    "dc:description": "Old logo file DO NOT USE",
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Obsolete-Logo'"
fi

# Create Logo-2024 (File)
if ! doc_exists "/default-domain/workspaces/Projects/Logo-2024"; then
    BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    echo "New Logo Content" > /tmp/newlogo.txt
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: logo_2024.txt" \
        -d "New Logo Content" > /dev/null

    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Logo-2024",
  "properties": {
    "dc:title": "Logo-2024",
    "dc:description": "The new approved logo",
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Logo-2024'"
fi

# Create Campaign-Overview (File)
if ! doc_exists "/default-domain/workspaces/Projects/Campaign-Overview"; then
    BATCH_RES=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    echo "Campaign Overview Content" > /tmp/campaign.txt
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: campaign.txt" \
        -d "Campaign Content" > /dev/null

    PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Campaign-Overview",
  "properties": {
    "dc:title": "Campaign-Overview",
    "dc:description": "Overview of Q3 strategy",
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Campaign-Overview'"
fi

# 4. Create the 'Brand Assets' Collection
# We'll create it inside the Projects workspace for easy finding, although Collections often live in User Workspaces.
echo "Creating collection..."
if ! doc_exists "/default-domain/workspaces/Projects/Brand-Assets"; then
    PAYLOAD='{"entity-type":"document","type":"Collection","name":"Brand-Assets","properties":{"dc:title":"Brand Assets","dc:description":"Old collection description"}}'
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" > /dev/null
    echo "Created 'Brand Assets' collection"
fi

# 5. Populate Collection with Obsolete Logo (The Starting State)
echo "Adding initial content to collection..."
# Get UIDs using python one-liner to parse JSON
OBSOLETE_UID=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Obsolete-Logo" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
COLLECTION_UID=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Brand-Assets" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

if [ -n "$OBSOLETE_UID" ] && [ -n "$COLLECTION_UID" ]; then
    # Use Nuxeo Automation API to add to collection
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/automation/Collection.AddToCollection" \
        -d "{\"params\":{\"collection\":\"$COLLECTION_UID\"},\"input\":\"$OBSOLETE_UID\"}" > /dev/null
    echo "Added Obsolete-Logo to Brand Assets"
fi

# 6. Launch Firefox and Login
# Ensure we start fresh
pkill -9 -f firefox || true
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Maximize Firefox (using wmctrl as ga user)
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Perform Login
nuxeo_login

# 7. Navigate to the Collection to save the agent time finding it
# This helps focus the task on "managing content" rather than "search"
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Brand-Assets"

# 8. Capture Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="