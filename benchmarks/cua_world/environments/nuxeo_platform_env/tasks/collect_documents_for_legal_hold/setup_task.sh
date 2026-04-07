#!/bin/bash
# Setup for collect_documents_for_legal_hold task
# Creates target documents and distractors in the Projects workspace.

echo "=== Setting up Legal Hold Discovery Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 180

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    create_doc "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Project files" > /dev/null
fi

# 4. Remove any existing 'Legal Hold - Acme' collection (clean state)
# Collections are usually stored in the user's workspace or default domain
# We'll search for it and delete if found
echo "Cleaning up old collections..."
COLLECTION_UID=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Legal+Hold+-+Acme'" \
    | python3 -c "import sys,json; entries=json.load(sys.stdin).get('entries',[]); print(entries[0]['uid']) if entries else print('')")

if [ -n "$COLLECTION_UID" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$COLLECTION_UID" > /dev/null
    echo "Deleted existing collection."
fi

# 5. Create Documents with specific content
# We use Note type for immediate indexing of text content without PDF conversion lag
echo "Creating documents..."

# Helper to create a Note
create_note_doc() {
    local title="$1"
    local name="$2"
    local content="$3"
    
    # Delete if exists
    if doc_exists "/default-domain/workspaces/Projects/$name"; then
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/$name" > /dev/null
    fi

    # Create
    local payload
    payload=$(jq -n \
        --arg type "Note" \
        --arg name "$name" \
        --arg title "$title" \
        --arg content "$content" \
        '{
            "entity-type": "document",
            "type": $type,
            "name": $name,
            "properties": {
                "dc:title": $title,
                "note:note": $content,
                "note:mime_type": "text/html"
            }
        }')
    
    nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$payload" > /dev/null
    echo "Created: $title"
}

# TARGET 1: Matches Title="Agreement" AND Content="Acme Corp"
create_note_doc "Acme Service Agreement" "Acme-Service-Agreement" \
    "<p>This Master Service Agreement is entered into by and between <strong>Acme Corp</strong> and the Provider.</p><p>Terms and conditions...</p>"

# TARGET 2: Matches Title="Agreement" AND Content="Acme Corp"
create_note_doc "Acme NDA Agreement" "Acme-NDA-Agreement" \
    "<p>Mutual Non-Disclosure Agreement.</p><p>Recipients: <strong>Acme Corp</strong> representatives...</p>"

# DISTRACTOR 1: Content match ("Acme Corp"), but Title mismatch ("Invoice")
create_note_doc "Acme Invoice 2023-001" "Acme-Invoice" \
    "<p>INVOICE #001</p><p>Bill To: <strong>Acme Corp</strong> Accounts Payable.</p><p>Amount: $5,000.00</p>"

# DISTRACTOR 2: Title match ("Agreement"), but Content mismatch ("Beta Inc" instead of Acme)
create_note_doc "Beta Service Agreement" "Beta-Service-Agreement" \
    "<p>Service Agreement for <strong>Beta Inc</strong>.</p><p>This document details the scope of work for Beta Inc projects.</p>"

# 6. Wait briefly for full-text indexing (Nuxeo creates async work for indexing)
echo "Waiting for indexing..."
sleep 5

# 7. Prepare Browser
echo "Launching browser..."
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Login
nuxeo_login

# Navigate to Projects
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"

# 8. Capture initial state
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="