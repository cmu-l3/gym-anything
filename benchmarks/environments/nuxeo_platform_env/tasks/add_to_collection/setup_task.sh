#!/bin/bash
# pre_task hook for add_to_collection task.
# Ensures the 'Q4 2023 Documents' collection exists.
# Removes the Annual Report from that collection (if already added).
# Then opens Firefox to the Annual Report 2023 document.

echo "=== Setting up add_to_collection task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Ensure the 'Q4 2023 Documents' collection exists
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='Q4+2023+Documents'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0")
COLL_COUNT=$(echo "$COLL_SEARCH" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(len(d.get('entries',[])))" 2>/dev/null || echo "0")

if [ "$COLL_COUNT" = "0" ]; then
    echo "Creating 'Q4 2023 Documents' collection in workspaces..."
    COLL_RESULT=$(curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
        -X POST "$NUXEO_URL/api/v1/path/default-domain/workspaces/" \
        -d '{"entity-type":"document","type":"Collection","name":"Q4-2023-Documents","properties":{"dc:title":"Q4 2023 Documents","dc:description":"Q4 2023 financial and project documents"}}')
    COLL_UID=$(echo "$COLL_RESULT" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
    echo "Collection created: UID=$COLL_UID"
else
    echo "'Q4 2023 Documents' collection already exists."
    COLL_UID=$(echo "$COLL_SEARCH" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); e=d.get('entries',[]); print(e[0].get('uid','') if e else '')" 2>/dev/null)
    # Remove Annual Report from collection if already added
    DOC_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023")
    if [ "$DOC_CODE" = "200" ] && [ -n "$COLL_UID" ]; then
        DOC_UID=$(curl -s -u "$NUXEO_AUTH" \
            "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)
        [ -n "$DOC_UID" ] && curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
            -X POST "$NUXEO_URL/api/v1/id/$COLL_UID/@op/Collection.RemoveFromCollection" \
            -d "{\"params\":{\"documents\":[\"$DOC_UID\"]}}" > /dev/null 2>&1 || true
    fi
fi

sleep 2

# Open Firefox, log in, navigate to Annual Report 2023
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
echo "Agent must use 'Add to Collection' and select 'Q4 2023 Documents'."
echo "=== add_to_collection task setup complete ==="
