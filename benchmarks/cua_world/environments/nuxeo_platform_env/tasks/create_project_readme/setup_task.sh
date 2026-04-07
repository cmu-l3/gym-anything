#!/bin/bash
# pre_task hook for create_project_readme task.
# 1. Ensures target documents (Annual Report, Proposal) exist.
# 2. Removes any pre-existing 'Project Readme' note.
# 3. Opens Firefox to the Projects workspace.

echo "=== Setting up create_project_readme task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_nuxeo 120

PROJECTS_PATH="/default-domain/workspaces/Projects"

# 1. Ensure 'Projects' workspace exists
if ! doc_exists "$PROJECTS_PATH"; then
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Active project documents"
fi

# 2. Ensure target documents exist (recreate if missing)
# Annual Report 2023
if ! doc_exists "$PROJECTS_PATH/Annual-Report-2023"; then
    echo "Creating missing Annual Report..."
    # If we have the file, upload it; otherwise create empty file doc
    if [ -f "/workspace/data/annual_report_2023.pdf" ]; then
        # This function is in task_utils.sh but simpler to recreate inline here if needed
        # We'll use a simplified create call
        create_doc_if_missing "$PROJECTS_PATH" "File" "Annual-Report-2023" "Annual Report 2023" "Financial report"
    else
        create_doc_if_missing "$PROJECTS_PATH" "File" "Annual-Report-2023" "Annual Report 2023" "Financial report"
    fi
fi

# Project Proposal
if ! doc_exists "$PROJECTS_PATH/Project-Proposal"; then
    echo "Creating missing Project Proposal..."
    create_doc_if_missing "$PROJECTS_PATH" "File" "Project-Proposal" "Project Proposal" "Initial proposal"
fi

# 3. Remove any existing 'Project Readme' note (Clean Slate)
# Check for common name variations
for name in "Project-Readme" "Project_Readme" "Project-Read-Me"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/path$PROJECTS_PATH/$name")
    if [ "$CODE" = "200" ]; then
        echo "Removing existing note: $name"
        curl -s -u "$NUXEO_AUTH" -X DELETE \
            "$NUXEO_URL/api/v1/path$PROJECTS_PATH/$name" || true
    fi
done

# Also search by title to be thorough
NOTES_TO_DELETE=$(curl -s -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=SELECT+*+FROM+Note+WHERE+ecm:path+STARTSWITH+'$PROJECTS_PATH'+AND+dc:title='Project+Readme'+AND+ecm:isTrashed=0" \
    | python3 -c "import sys, json; print(' '.join([d['uid'] for d in json.load(sys.stdin).get('entries', [])]))" 2>/dev/null)

if [ -n "$NOTES_TO_DELETE" ]; then
    for uid in $NOTES_TO_DELETE; do
        echo "Deleting note by UID: $uid"
        curl -s -u "$NUXEO_AUTH" -X DELETE "$NUXEO_URL/api/v1/id/$uid" || true
    done
fi

sleep 2

# 4. Open Firefox, log in, navigate to Projects workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse$PROJECTS_PATH"
sleep 4

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "Task start state: Firefox is on the Projects workspace."
echo "Agent must create a Note titled 'Project Readme' with links."
echo "=== create_project_readme task setup complete ==="