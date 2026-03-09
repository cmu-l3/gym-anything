#!/bin/bash
# pre_task hook for create_collection task.
# Removes the '2024 Planning Documents' collection if it exists,
# then opens Firefox to the home page so the agent can create it.

echo "=== Setting up create_collection task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Remove the collection if it already exists (search and delete)
COLL_SEARCH=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+WHERE+dc:title='2024+Planning+Documents'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0")
echo "$COLL_SEARCH" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for doc in data.get('entries', []):
    print(doc.get('uid',''))
" 2>/dev/null | while read -r uid; do
    if [ -n "$uid" ]; then
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" > /dev/null || true
        echo "Deleted collection $uid"
    fi
done

sleep 2

# Open Firefox, log in, navigate to home
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/home"
sleep 4

echo "Task start state: Firefox is on the Nuxeo home page."
echo "Agent must create a Collection named '2024 Planning Documents'."
echo "Tip: Use the left sidebar 'Collections' icon or the + button to create a new collection."
echo "=== create_collection task setup complete ==="
