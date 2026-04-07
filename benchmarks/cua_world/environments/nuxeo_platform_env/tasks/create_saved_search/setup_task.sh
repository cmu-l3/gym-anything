#!/bin/bash
# Setup for create_saved_search task
# Ensures Nuxeo is running, required documents exist, and clean state for saved search.

set -e
echo "=== Setting up create_saved_search task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 3. Clean up: Delete any pre-existing 'Project Reports Search'
# We query for it first to get the ID, then delete it.
echo "Cleaning up any pre-existing saved searches..."
SEARCH_HITS=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+SavedSearch+WHERE+dc:title='Project+Reports+Search'+AND+ecm:isTrashed=0")

# Extract UIDs and delete them
echo "$SEARCH_HITS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for doc in data.get('entries', []):
        print(doc.get('uid', ''))
except:
    pass
" | while read -r uid; do
    if [ -n "$uid" ]; then
        echo "  Deleting existing saved search: $uid"
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" > /dev/null 2>&1 || true
    fi
done

# 4. Verify/Create prerequisite documents
echo "Verifying prerequisite documents..."

# Helper to check/upload PDF
ensure_pdf_doc() {
    local name="$1"
    local title="$2"
    local local_file="$3"
    local parent="/default-domain/workspaces/Projects"
    
    # Check if exists
    if ! doc_exists "$parent/$name"; then
        echo "  Creating $name..."
        # Upload file
        if [ -f "$local_file" ]; then
            BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")
            if [ -n "$BATCH_ID" ]; then
                 curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
                    -H "X-File-Name: $(basename "$local_file")" \
                    -H "Content-Type: application/octet-stream" \
                    --data-binary @"$local_file" > /dev/null
                 
                 # Create Document
                 PAYLOAD="{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"$name\",\"properties\":{\"dc:title\":\"$title\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}"
                 nuxeo_api POST "/path$parent/" "$PAYLOAD" > /dev/null
            fi
        else
            echo "  WARNING: Local file $local_file not found. Skipping $name."
        fi
    else
        echo "  $name already exists."
    fi
}

# Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Workspace for projects"
fi

# Ensure documents exist
ensure_pdf_doc "Annual-Report-2023" "Annual Report 2023" "/workspace/data/annual_report_2023.pdf"
ensure_pdf_doc "Project-Proposal" "Project Proposal" "/workspace/data/project_proposal.pdf"

# Ensure Note exists
if ! doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report"; then
    echo "  Creating Q3 Status Report..."
    NOTE_PAYLOAD='{"entity-type":"document","type":"Note","name":"Q3-Status-Report","properties":{"dc:title":"Q3 Status Report","dc:description":"Quarterly status report for Q3 2023","note:note":"<p>This is the Q3 2023 status report. Key highlights: Phase 1 complete, budget on track.</p>"}}'
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$NOTE_PAYLOAD" > /dev/null
fi

# 5. Launch Firefox and Login
# We restart Firefox to ensure a clean session
pkill -f firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Perform login automation
nuxeo_login

# 6. Capture initial state
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="