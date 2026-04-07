#!/bin/bash
set -e
echo "=== Setting up organize_documents_into_collections task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Ensure Documents Exist in Projects Workspace
# The base environment setup might have created them, but we ensure they are clean.

echo "Ensuring required documents exist..."

# Function to ensure a specific document exists
ensure_doc() {
    local path="$1"
    local type="$2"
    local title="$3"
    
    if ! doc_exists "$path"; then
        echo "Creating missing document: $title"
        # Create parent structure if needed (simplified assumption: Projects exists)
        local parent=$(dirname "$path")
        local name=$(basename "$path")
        
        # Simple creation payload
        local payload="{\"entity-type\":\"document\",\"type\":\"$type\",\"name\":\"$name\",\"properties\":{\"dc:title\":\"$title\"}}"
        nuxeo_api POST "/path$parent/" "$payload" > /dev/null
    fi
}

# Ensure the Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects"
fi

# Ensure the specific files exist
# Note: valid PDF upload is complex via curl in setup, so we ensure the Doc object exists.
# If the file content is missing, the metadata is sufficient for Collection testing.
ensure_doc "/default-domain/workspaces/Projects/Annual-Report-2023" "File" "Annual Report 2023"
ensure_doc "/default-domain/workspaces/Projects/Project-Proposal" "File" "Project Proposal"
ensure_doc "/default-domain/workspaces/Projects/Q3-Status-Report" "Note" "Q3 Status Report"

# 4. Clean up any existing Collections with the target names
# We search for them and delete them to ensure a fresh start.
echo "Cleaning up old collections..."

delete_collection() {
    local title="$1"
    # Search for collection by title
    local query="SELECT * FROM Collection WHERE dc:title = '$title' AND ecm:isTrashed = 0"
    local response=$(curl -s -u "$NUXEO_AUTH" -G --data-urlencode "query=$query" "$NUXEO_URL/api/v1/search/lang/NXQL/execute")
    
    # Extract UIDs and delete
    echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for doc in data.get('entries', []):
    print(doc['uid'])
" | while read uid; do
        if [ -n "$uid" ]; then
            echo "Deleting existing collection '$title' (uid: $uid)"
            nuxeo_api DELETE "/id/$uid"
        fi
    done
}

delete_collection "Finance Resources"
delete_collection "Strategy Resources"

# 5. Launch Firefox and Login
# We open Firefox to the Projects workspace
echo "Launching Firefox..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Check if we need to login (if title doesn't contain Nuxeo)
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if [[ "$PAGE_TITLE" != *"Nuxeo"* ]]; then
    nuxeo_login
fi

# Navigate to Projects workspace
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# 6. Capture Initial State
ga_x "scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="