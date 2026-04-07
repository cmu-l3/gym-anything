#!/bin/bash
set -e
echo "=== Setting up generate_document_audit_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be fully ready
wait_for_nuxeo 120

# 3. Ensure the Projects workspace exists
if ! doc_exists "/default-domain/workspaces/Projects"; then
    echo "Creating Projects workspace..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" \
        "Projects" "Project management workspace"
fi

# 4. Ensure there are documents in the workspace
# We need at least 2 documents to satisfy the task requirements
DOC_COUNT=$(nuxeo_api GET "/query?query=SELECT+*+FROM+Document+WHERE+ecm:path+STARTSWITH+'/default-domain/workspaces/Projects'+AND+ecm:mixinType!='HiddenInNavigation'+AND+ecm:isProxy=0+AND+ecm:isTrashed=0" | python3 -c "import sys,json; print(json.load(sys.stdin).get('resultsCount',0))" 2>/dev/null || echo "0")

if [ "$DOC_COUNT" -lt 2 ]; then
    echo "Creating seed documents..."
    # Create Document 1
    create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Kickoff-Meeting" \
        "Kickoff Meeting" "Notes from the kickoff"
    
    # Create Document 2
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Budget-Draft" \
        "Budget Draft" "Initial budget estimation"
fi

# 5. Generate fresh audit events (Anti-gaming: ensure audit trail is not stale)
# Modify a document to create a 'documentModified' event right now
echo "Generating fresh audit events..."
TARGET_DOC_PATH="/default-domain/workspaces/Projects/Kickoff-Meeting"
if ! doc_exists "$TARGET_DOC_PATH"; then
    # Fallback if specific doc doesn't exist, pick the first one found
    TARGET_DOC_UID=$(nuxeo_api GET "/query?query=SELECT+*+FROM+Document+WHERE+ecm:path+STARTSWITH+'/default-domain/workspaces/Projects'" | python3 -c "import sys,json; print(json.load(sys.stdin)['entries'][0]['uid'])" 2>/dev/null)
else
    TARGET_DOC_UID=$(nuxeo_api GET "/path$TARGET_DOC_PATH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
fi

if [ -n "$TARGET_DOC_UID" ]; then
    TIMESTAMP=$(date +%s)
    # Update description to force an audit log entry
    nuxeo_api PUT "/id/$TARGET_DOC_UID" "{\"entity-type\":\"document\",\"properties\":{\"dc:description\":\"Updated for audit verification $TIMESTAMP\"}}" > /dev/null
    echo "Updated document $TARGET_DOC_UID to generate audit entry"
fi

# 6. Remove any existing result file
rm -f /home/ga/audit_report.json

# 7. Open Firefox and log in (Agent starting state)
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 10
nuxeo_login

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="