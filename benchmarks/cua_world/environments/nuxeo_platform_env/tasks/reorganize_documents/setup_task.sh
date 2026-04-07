#!/bin/bash
set -e

echo "=== Setting up reorganize_documents task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be ready
wait_for_nuxeo 120

# ---------------------------------------------------------------------------
# Helper to get UID by path
# ---------------------------------------------------------------------------
get_uid_by_path() {
    curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path$1" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uid', ''))" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Step 1: Clean up previous runs (delete folders if they exist)
# ---------------------------------------------------------------------------
echo "Cleaning up workspace..."

# Check for and delete Financial Reports folder
FR_UID=$(get_uid_by_path "/default-domain/workspaces/Projects/Financial-Reports")
if [ -n "$FR_UID" ]; then
    echo "Removing existing Financial Reports folder..."
    # Move children back to root before deleting folder (to preserve docs if possible)
    # Actually, easier to just delete and let the restore step handle recreation if needed,
    # but we want to preserve UIDs if possible.
    # For simplicity in setup, we'll delete the folders.
    # The environment setup usually ensures the docs exist.
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$FR_UID" > /dev/null
fi

# Check for and delete Proposals folder
PR_UID=$(get_uid_by_path "/default-domain/workspaces/Projects/Proposals")
if [ -n "$PR_UID" ]; then
    echo "Removing existing Proposals folder..."
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$PR_UID" > /dev/null
fi

# ---------------------------------------------------------------------------
# Step 2: Ensure source documents exist at Projects root
# ---------------------------------------------------------------------------
echo "Verifying source documents..."

PROJECTS_UID=$(get_uid_by_path "/default-domain/workspaces/Projects")
if [ -z "$PROJECTS_UID" ]; then
    echo "ERROR: Projects workspace not found!"
    exit 1
fi

# We need to make sure the 3 specific documents exist at the root.
# If they don't exist (deleted or moved elsewhere), we recreate them.

ensure_doc() {
    local title="$1"
    local name="$2"
    local type="$3"
    
    # Search for doc by title in Projects folder
    local query="SELECT * FROM Document WHERE ecm:parentId = '$PROJECTS_UID' AND dc:title = '$title' AND ecm:isTrashed = 0"
    local count=$(nuxeo_api GET "/search/lang/NXQL/execute?query=$(echo "$query" | python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip()))')" | \
        python3 -c "import sys,json; print(len(json.load(sys.stdin).get('entries', [])))")
    
    if [ "$count" -eq "0" ]; then
        echo "Creating missing document: $title"
        # Create a simple placeholder if it's missing. 
        # In a real scenario, we might copy the PDF again, but for this task logic, 
        # the existence and metadata is sufficient.
        local payload="{\"entity-type\":\"document\",\"type\":\"$type\",\"name\":\"$name\",\"properties\":{\"dc:title\":\"$title\"}}"
        nuxeo_api POST "/path/default-domain/workspaces/Projects" "$payload" > /dev/null
    fi
}

ensure_doc "Annual Report 2023" "Annual-Report-2023" "File"
ensure_doc "Project Proposal" "Project-Proposal" "File"
ensure_doc "Q3 Status Report" "Q3-Status-Report" "Note"

# ---------------------------------------------------------------------------
# Step 3: Record Initial State (UIDs)
# ---------------------------------------------------------------------------
echo "Recording initial state..."

# Fetch the UIDs of the documents at the root to verify later that they were moved (same UID) not copied
# We use a python script to dump specific details to a JSON file
python3 -c "
import requests, json, os

auth = ('Administrator', 'Administrator')
url = 'http://localhost:8080/nuxeo/api/v1/search/lang/NXQL/execute'
projects_uid = '$PROJECTS_UID'
query = f\"SELECT * FROM Document WHERE ecm:parentId = '{projects_uid}' AND ecm:isTrashed = 0\"

try:
    r = requests.get(url, params={'query': query}, auth=auth)
    data = r.json()
    entries = data.get('entries', [])
    
    initial_map = {}
    for doc in entries:
        title = doc.get('title')
        uid = doc.get('uid')
        if title in ['Annual Report 2023', 'Project Proposal', 'Q3 Status Report']:
            initial_map[title] = uid
            
    with open('/tmp/initial_doc_uids.json', 'w') as f:
        json.dump(initial_map, f)
    print('Initial UIDs recorded:', initial_map)
except Exception as e:
    print('Error recording state:', e)
"

# ---------------------------------------------------------------------------
# Step 4: Prepare UI
# ---------------------------------------------------------------------------
echo "Opening Firefox..."

# Open Nuxeo URL
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 10

# Handle Login
nuxeo_login

# Ensure we are at the right location
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="