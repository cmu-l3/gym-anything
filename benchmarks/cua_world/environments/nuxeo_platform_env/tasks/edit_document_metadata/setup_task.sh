#!/bin/bash
# pre_task hook for edit_document_metadata task.
# Resets the description of 'Annual Report 2023' to a blank value,
# then opens Firefox directly to that document.

echo "=== Setting up edit_document_metadata task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Ensure the Annual Report 2023 document exists; recreate if missing
DOC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023")

if [ "$DOC_CODE" != "200" ]; then
    echo "Document not found; recreating..."
    DATA_FILE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    [ ! -f "$DATA_FILE" ] && DATA_FILE="/workspace/data/Annual_Report_2023.pdf"
    if [ -f "$DATA_FILE" ]; then
        BATCH_RESP=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/")
        BATCH_ID=$(echo "$BATCH_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))" 2>/dev/null)
        if [ -n "$BATCH_ID" ]; then
            curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
                -H "X-File-Name: annual_report_2023.pdf" -H "X-File-Type: application/pdf" \
                --data-binary @"$DATA_FILE" > /dev/null
            curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
                -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/" \
                -d "{\"entity-type\":\"document\",\"type\":\"File\",\"name\":\"Annual-Report-2023\",\"properties\":{\"dc:title\":\"Annual Report 2023\",\"dc:description\":\"\",\"file:content\":{\"upload-batch\":\"$BATCH_ID\",\"upload-fileId\":\"0\"}}}" > /dev/null
            echo "Annual Report 2023 recreated."
        fi
    fi
else
    # Reset description to empty
    curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X PUT "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023" \
        -d '{"entity-type":"document","properties":{"dc:description":""}}' > /dev/null
    echo "Reset description of Annual Report 2023."
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

echo "Task start state: Firefox is on the Annual Report 2023 document view."
echo "Agent must edit the description field and save the changes."
echo "=== edit_document_metadata task setup complete ==="
