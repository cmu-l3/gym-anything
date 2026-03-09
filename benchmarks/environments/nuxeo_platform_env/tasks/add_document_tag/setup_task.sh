#!/bin/bash
# pre_task hook for add_document_tag task.
# Ensures Annual Report 2023 has NO 'finance' tag, then opens Firefox to the document.

echo "=== Setting up add_document_tag task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Remove the 'finance' tag from the document (reset state)
DOC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023")
if [ "$DOC_CODE" = "200" ]; then
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023/@op/Document.RemoveTag" \
        -d '{"params":{"value":"finance"}}' > /dev/null 2>&1 || true
    echo "Removed 'finance' tag (if it existed)."
fi

sleep 2

# Open Firefox, log in, navigate to the document
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Annual-Report-2023"
sleep 4

echo "Task start state: Firefox is on the Annual Report 2023 document."
echo "Agent must add the tag 'finance' to the document."
echo "=== add_document_tag task setup complete ==="
