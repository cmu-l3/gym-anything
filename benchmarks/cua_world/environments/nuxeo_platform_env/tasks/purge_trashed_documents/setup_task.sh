#!/bin/bash
# Setup script for purge_trashed_documents
# Creates a workspace, uploads documents, and moves them to trash.

set -e
echo "=== Setting up Purge Trashed Documents task ==="

# Source shared Nuxeo utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 180

# ---------------------------------------------------------------------------
# 1. Clean up previous run (if any)
# ---------------------------------------------------------------------------
echo "Cleaning up previous state..."
curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/ClientRecords" >/dev/null 2>&1 || true
# Wait for async deletion
sleep 2

# ---------------------------------------------------------------------------
# 2. Create Workspace
# ---------------------------------------------------------------------------
echo "Creating ClientRecords workspace..."
create_doc_if_missing "/default-domain/workspaces" "Workspace" "ClientRecords" \
    "Client Records" "Repository for client agreements and financial records"

# ---------------------------------------------------------------------------
# 3. Create Documents (using Real Data)
# ---------------------------------------------------------------------------
echo "Creating documents..."

# Helper to upload PDF and create file
# Usage: create_file_doc "LocalPath" "DocName" "DocTitle"
create_file_doc() {
    local src="$1"
    local name="$2"
    local title="$3"
    
    # Upload file
    local filesize=$(stat -c%s "$src")
    local filename=$(basename "$src")
    
    BATCH_OUT=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
    BATCH_ID=$(echo "$BATCH_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
    
    curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
        -H "Content-Type: application/octet-stream" \
        -H "X-File-Name: $filename" \
        -H "X-File-Size: $filesize" \
        --data-binary @"$src" > /dev/null
        
    # Create doc
    local payload=$(cat <<EOF
{
  "entity-type": "document",
  "type": "File",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "file:content": { "upload-batch": "$BATCH_ID", "upload-fileId": "0" }
  }
}
EOF
)
    # Return UID
    nuxeo_api POST "/path/default-domain/workspaces/ClientRecords/" "$payload" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))"
}

# Helper to create Note
create_note_doc() {
    local name="$1"
    local title="$2"
    local content="$3"
    
    local payload=$(cat <<EOF
{
  "entity-type": "document",
  "type": "Note",
  "name": "$name",
  "properties": {
    "dc:title": "$title",
    "note:note": "$content"
  }
}
EOF
)
    nuxeo_api POST "/path/default-domain/workspaces/ClientRecords/" "$payload" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))"
}

# --- Create Purge Targets ---
# Use real PDFs from workspace data if available
PDF_1="/workspace/data/annual_report_2023.pdf"
PDF_2="/workspace/data/project_proposal.pdf"
[ -f "$PDF_1" ] || PDF_1="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
[ -f "$PDF_2" ] || PDF_2="/home/ga/nuxeo/data/Project_Proposal.pdf"

echo "Creating Anderson record..."
UID_ANDERSON=$(create_file_doc "$PDF_1" "Anderson-Account-Agreement-2016" "Anderson Account Agreement 2016")

echo "Creating Baker record..."
UID_BAKER=$(create_file_doc "$PDF_2" "Baker-Loan-Application-2015" "Baker Loan Application 2015")

echo "Creating Chen record..."
UID_CHEN=$(create_note_doc "Chen-Investment-Portfolio-2014" "Chen Investment Portfolio 2014" \
    "<p>Portfolio composition for FY 2014. Risk profile: Aggressive.</p>")

# --- Create Preserve Targets ---
echo "Creating Davis record..."
UID_DAVIS=$(create_file_doc "$PDF_1" "Davis-Mortgage-Records-2018" "Davis Mortgage Records 2018")

echo "Creating Evans record..."
UID_EVANS=$(create_note_doc "Evans-Trust-Documents-2019" "Evans Trust Documents 2019" \
    "<p>Revocable Living Trust established 2019. <b>LEGAL HOLD ACTIVE.</b></p>")

# ---------------------------------------------------------------------------
# 4. Trash Documents
# ---------------------------------------------------------------------------
echo "Trashing all documents..."

trash_doc() {
    local uid="$1"
    # Execute 'Document.Trash' operation
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/id/$uid/@op/Document.Trash" > /dev/null
}

trash_doc "$UID_ANDERSON"
trash_doc "$UID_BAKER"
trash_doc "$UID_CHEN"
trash_doc "$UID_DAVIS"
trash_doc "$UID_EVANS"

# ---------------------------------------------------------------------------
# 5. Save State for Verification
# ---------------------------------------------------------------------------
cat <<EOF > /tmp/task_doc_uids.json
{
  "purge": {
    "Anderson": "$UID_ANDERSON",
    "Baker": "$UID_BAKER",
    "Chen": "$UID_CHEN"
  },
  "preserve": {
    "Davis": "$UID_DAVIS",
    "Evans": "$UID_EVANS"
  }
}
EOF

echo "Initial state saved to /tmp/task_doc_uids.json"
chmod 666 /tmp/task_doc_uids.json

# ---------------------------------------------------------------------------
# 6. Prepare UI
# ---------------------------------------------------------------------------
# Open Firefox to login page, authenticate, then go to workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 10
nuxeo_login
sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/ClientRecords"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="