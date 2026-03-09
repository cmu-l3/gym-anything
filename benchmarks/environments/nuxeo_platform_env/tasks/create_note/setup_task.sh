#!/bin/bash
# pre_task hook for create_note task.
# Removes any existing 'Meeting Minutes - October 2023' note,
# then opens Firefox to the Projects workspace.

echo "=== Setting up create_note task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Remove existing note if it exists
for name in "Meeting-Minutes-October-2023" "Meeting-Minutes---October-2023"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/$name")
    if [ "$CODE" = "200" ]; then
        curl -s -u "$NUXEO_AUTH" -X DELETE \
            "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/$name" || true
        sleep 2
    fi
done

# Search for any Notes with "October 2023" in title and delete
NOTES=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Note+WHERE+ecm:path+STARTSWITH+'/default-domain/workspaces/Projects'+AND+dc:title+LIKE+'%25October+2023%25'+AND+ecm:isTrashed=0+AND+ecm:isVersion=0")
echo "$NOTES" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for doc in data.get('entries', []):
    print(doc.get('uid',''))
" 2>/dev/null | while read -r uid; do
    [ -n "$uid" ] && curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" > /dev/null 2>&1 || true
done
sleep 2

# Open Firefox, log in, navigate to Projects workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 4

echo "Task start state: Firefox is on the Projects workspace."
echo "Agent must create a Note titled 'Meeting Minutes - October 2023' with content about action items."
echo "=== create_note task setup complete ==="
