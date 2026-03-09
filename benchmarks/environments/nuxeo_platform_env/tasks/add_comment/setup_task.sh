#!/bin/bash
# pre_task hook for add_comment task.
# Removes any existing comments on the Project Proposal document,
# then opens Firefox to that document.

echo "=== Setting up add_comment task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Ensure Project Proposal document exists
DOC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Project-Proposal")
if [ "$DOC_CODE" != "200" ]; then
    echo "Project Proposal not found; recreating..."
    DATA_FILE="/home/ga/nuxeo/data/Project_Proposal.pdf"
    [ ! -f "$DATA_FILE" ] && DATA_FILE="/workspace/data/Project_Proposal.pdf"
    if [ -f "$DATA_FILE" ]; then
        BATCH_RESP=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
        BATCH_ID=$(echo "$BATCH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
        if [ -n "$BATCH_ID" ]; then
            curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
                -H "X-File-Name: project_proposal.pdf" -H "X-File-Type: application/pdf" \
                --data-binary @"$DATA_FILE" > /dev/null
            curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
                -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/" \
                -d "{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"Project-Proposal\",\"properties\":{\"dc:title\":\"Project Proposal\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}" > /dev/null
            echo "Project Proposal recreated."
        fi
    fi
fi

# Remove existing comments (if any)
COMMENTS=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Project-Proposal/@comment")
echo "$COMMENTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('entries', []):
    print(c.get('id',''))
" 2>/dev/null | while read -r cid; do
    [ -n "$cid" ] && curl -s -u "$NUXEO_AUTH" \
        -X DELETE "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Project-Proposal/@comment/$cid" \
        > /dev/null 2>&1 || true
done

sleep 2

# Open Firefox, log in, navigate to Project Proposal
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Project-Proposal"
sleep 4

echo "Task start state: Firefox is on the Project Proposal document."
echo "Agent must add comment: 'Please review and approve by end of week. Feedback needed on budget section.'"
echo "=== add_comment task setup complete ==="
