#!/bin/bash
# Setup script for process_digital_mailroom
# Creates the Drop Box and target workspaces, and populates the Drop Box with "scanned" files.

set -e
echo "=== Setting up process_digital_mailroom task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# 1. Clean up and Create Folder Structure
# ---------------------------------------------------------------------------
echo "Setting up workspace structure..."

# Define paths
DROP_BOX_PATH="/default-domain/workspaces/Drop-Box"
CONTRACTS_PATH="/default-domain/workspaces/Contracts"
INVOICES_PATH="/default-domain/workspaces/Invoices"
ASSETS_PATH="/default-domain/workspaces/Assets"

# Helper to delete and recreate a workspace
reset_workspace() {
    local name="$1"
    local title="$2"
    local path="/default-domain/workspaces/$name"
    
    # Check if exists
    if doc_exists "$path"; then
        echo "Resetting existing workspace: $name"
        # Delete it (and its children)
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path$path" >/dev/null
        sleep 2
    fi
    
    # Create it
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "$name" "$title" "Task workspace" >/dev/null
    echo "Created workspace: $title"
}

reset_workspace "Drop-Box" "Drop Box"
reset_workspace "Contracts" "Contracts"
reset_workspace "Invoices" "Invoices"
reset_workspace "Assets" "Assets"

sleep 2

# ---------------------------------------------------------------------------
# 2. Prepare Local Files for Upload
# ---------------------------------------------------------------------------
echo "Preparing document files..."
TEMP_DATA="/tmp/nuxeo_task_data"
mkdir -p "$TEMP_DATA"

# File 1: Contract (Source: Contract_Template.pdf)
# Fallback to creating a dummy PDF if source missing
if [ -f "/workspace/data/Contract_Template.pdf" ]; then
    cp "/workspace/data/Contract_Template.pdf" "$TEMP_DATA/Scan_Contract_Acme_v2.pdf"
elif [ -f "/home/ga/nuxeo/data/Contract_Template.pdf" ]; then
    cp "/home/ga/nuxeo/data/Contract_Template.pdf" "$TEMP_DATA/Scan_Contract_Acme_v2.pdf"
else
    echo "Using dummy PDF for contract"
    echo "%PDF-1.4 dummy content" > "$TEMP_DATA/Scan_Contract_Acme_v2.pdf"
fi

# File 2: Invoice (Source: Annual_Report_2023.pdf - just as content source)
if [ -f "/workspace/data/annual_report_2023.pdf" ]; then
    cp "/workspace/data/annual_report_2023.pdf" "$TEMP_DATA/Scan_Invoice_992_Q3.pdf"
elif [ -f "/home/ga/nuxeo/data/Annual_Report_2023.pdf" ]; then
    cp "/home/ga/nuxeo/data/Annual_Report_2023.pdf" "$TEMP_DATA/Scan_Invoice_992_Q3.pdf"
else
    echo "Using dummy PDF for invoice"
    echo "%PDF-1.4 dummy content" > "$TEMP_DATA/Scan_Invoice_992_Q3.pdf"
fi

# File 3: Site Photo (Generate a dummy JPEG)
# Convert a solid color to jpg using imagemagick if available, else simple text
if command -v convert >/dev/null 2>&1; then
    convert -size 640x480 xc:skyblue "$TEMP_DATA/IMG_Site_Photo_0023.jpg"
else
    echo "dummy image" > "$TEMP_DATA/IMG_Site_Photo_0023.jpg"
fi

# ---------------------------------------------------------------------------
# 3. Upload Files to Drop Box
# ---------------------------------------------------------------------------
echo "Uploading files to Drop Box..."

upload_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local type="$2" # "File" or "Picture"
    
    # 1. Get Batch ID
    local batch_resp
    batch_resp=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    local batch_id
    batch_id=$(echo "$batch_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    # 2. Upload blob
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$batch_id/0" \
        -H "X-File-Name: $filename" \
        --data-binary @"$filepath" >/dev/null
        
    # 3. Create Document
    local payload
    payload=$(cat <<EOF
{
  "entity-type": "document",
  "type": "$type",
  "name": "$filename",
  "properties": {
    "dc:title": "$filename",
    "file:content": {
      "upload-batch": "$batch_id",
      "upload-fileId": "0"
    }
  }
}
EOF
)
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/path$DROP_BOX_PATH" \
        -d "$payload" >/dev/null
    echo "  Uploaded $filename"
}

upload_file "$TEMP_DATA/Scan_Contract_Acme_v2.pdf" "File"
upload_file "$TEMP_DATA/Scan_Invoice_992_Q3.pdf" "File"
# Note: Nuxeo Picture type requires nuxeo-imaging package, usually File works for all, 
# but we'll use File to be safe as standard install might vary.
upload_file "$TEMP_DATA/IMG_Site_Photo_0023.jpg" "File" 

# ---------------------------------------------------------------------------
# 4. Prepare Browser
# ---------------------------------------------------------------------------
# Kill any existing Firefox and restart
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login if needed (helper checks window title)
sleep 5
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q "Nuxeo"; then
    nuxeo_login
fi

# Navigate to Drop Box
navigate_to "$NUXEO_UI/#!/browse$DROP_BOX_PATH"

# Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="