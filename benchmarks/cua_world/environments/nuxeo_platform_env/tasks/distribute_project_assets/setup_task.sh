#!/bin/bash
# Setup script for distribute_project_assets
# Creates the necessary workspace structure and documents, records initial UUIDs.

set -e
echo "=== Setting up distribute_project_assets task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 180

echo "Creating workspace structure..."

# 1. Create Parent Containers if missing
# /default-domain/workspaces/Active-Projects
if ! doc_exists "/default-domain/workspaces/Active-Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Active-Projects" "Active Projects" "Container for running projects"
fi

# /default-domain/workspaces/Archives
if ! doc_exists "/default-domain/workspaces/Archives"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Archives" "Archives" "Project Archives"
fi

# /default-domain/workspaces/Templates
if ! doc_exists "/default-domain/workspaces/Templates"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" "Templates" "Resource Library"
fi

# 2. Create Leaf Workspaces
# Source: /default-domain/workspaces/Active-Projects/Project-Omega
if ! doc_exists "/default-domain/workspaces/Active-Projects/Project-Omega"; then
    create_doc_if_missing "/default-domain/workspaces/Active-Projects" "Workspace" "Project-Omega" "Project Omega" "Project Omega Workspace"
fi

# Dest 1: /default-domain/workspaces/Archives/2023
if ! doc_exists "/default-domain/workspaces/Archives/2023"; then
    create_doc_if_missing "/default-domain/workspaces/Archives" "Workspace" "2023" "2023 Archives" "Archives for year 2023"
fi

# Dest 2: /default-domain/workspaces/Templates/Library
if ! doc_exists "/default-domain/workspaces/Templates/Library"; then
    create_doc_if_missing "/default-domain/workspaces/Templates" "Workspace" "Library" "Library" "Shared Template Library"
fi

echo "Creating content in Project Omega..."

# 3. Create 'Project Closure Report' (File)
# We use a real PDF if available, or generate a dummy if not
REPORT_PATH="/default-domain/workspaces/Active-Projects/Project-Omega/Project-Closure-Report"
if ! doc_exists "$REPORT_PATH"; then
    # Use existing PDF from environment data or generate one
    PDF_SOURCE="/workspace/data/annual_report_2023.pdf"
    if [ ! -f "$PDF_SOURCE" ]; then
        PDF_SOURCE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    fi
    
    if [ -f "$PDF_SOURCE" ]; then
        # Upload file logic
        BATCH_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
        BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
        
        FILENAME="Project_Closure_Report.pdf"
        FILESIZE=$(stat -c%s "$PDF_SOURCE")
        
        curl -s -u "$NUXEO_AUTH" \
            -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
            -H "Content-Type: application/octet-stream" \
            -H "X-File-Name: $FILENAME" \
            -H "X-File-Type: application/pdf" \
            -H "X-File-Size: $FILESIZE" \
            --data-binary @"$PDF_SOURCE" > /dev/null

        PAYLOAD=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "Project-Closure-Report",
  "properties": {
    "dc:title": "Project Closure Report",
    "dc:description": "Final report for Project Omega",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOF
)
        nuxeo_api POST "/path/default-domain/workspaces/Active-Projects/Project-Omega/" "$PAYLOAD" > /dev/null
        echo "Created Project Closure Report."
    else
        # Fallback if no PDF found (shouldn't happen in this env, but safe fallback)
        create_doc_if_missing "/default-domain/workspaces/Active-Projects/Project-Omega" "File" "Project-Closure-Report" "Project Closure Report" "Final Report"
    fi
fi

# 4. Create 'Reusable Assets' (Folder)
ASSETS_PATH="/default-domain/workspaces/Active-Projects/Project-Omega/Reusable-Assets"
if ! doc_exists "$ASSETS_PATH"; then
    create_doc_if_missing "/default-domain/workspaces/Active-Projects/Project-Omega" "Folder" "Reusable-Assets" "Reusable Assets" "Assets to be shared"
    # Create a dummy child item inside to make it realistic
    create_doc_if_missing "/default-domain/workspaces/Active-Projects/Project-Omega/Reusable-Assets" "Note" "ReadMe" "ReadMe" "Asset instructions" > /dev/null
fi

# 5. Record Initial State (UUIDs) for Verification
# We need to know the original UUIDs to distinguish between Move (keeps UUID) and Copy (new UUID)
echo "Recording initial UUIDs..."

REPORT_UID=$(nuxeo_api GET "/path$REPORT_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")
ASSETS_UID=$(nuxeo_api GET "/path$ASSETS_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

cat > /tmp/initial_state.json <<EOF
{
  "report_uid": "$REPORT_UID",
  "assets_uid": "$ASSETS_UID",
  "timestamp": "$(date +%s)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# 6. Setup Browser
# Kill existing firefox
pkill -9 -f firefox 2>/dev/null || true

# Launch Firefox and login
open_nuxeo_url "$NUXEO_URL/login.jsp" 10
nuxeo_login

# Navigate to the starting workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Active-Projects/Project-Omega"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="