#!/bin/bash
set -e

echo "=== Setting up Lock and Comment Document task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for Nuxeo to be ready
wait_for_nuxeo 120

DOC_PATH="/default-domain/workspaces/Templates/Contract-Template"
PARENT_PATH="/default-domain/workspaces/Templates"

# 3. Ensure the Templates workspace exists
if ! doc_exists "$PARENT_PATH"; then
    echo "Creating Templates workspace..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Templates" \
        "Templates" "Document templates"
fi

# 4. Ensure the Contract Template document exists
if ! doc_exists "$DOC_PATH"; then
    echo "Contract Template not found — creating it..."
    # Copy a real PDF if available for realism
    PDF_SOURCE="/workspace/data/Contract_Template.pdf"
    [ ! -f "$PDF_SOURCE" ] && PDF_SOURCE="/home/ga/nuxeo/data/Contract_Template.pdf"
    
    if [ -f "$PDF_SOURCE" ]; then
        # Create with file content if possible (requires upload batch logic, simplified here to create doc first)
         create_doc_if_missing "$PARENT_PATH" "File" \
            "Contract-Template" "Contract Template" \
            "Standard contract template for client engagements"
    else
        create_doc_if_missing "$PARENT_PATH" "File" \
            "Contract-Template" "Contract Template" \
            "Standard contract template for client engagements"
    fi
    sleep 2
fi

# 5. Get document UID
DOC_UID=$(curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/path$DOC_PATH" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null || echo "")
echo "$DOC_UID" > /tmp/contract_template_uid.txt
echo "Target Document UID: $DOC_UID"

# 6. CLEAN STATE: Ensure document is UNLOCKED
echo "Ensuring document is unlocked..."
LOCK_OWNER=$(curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/path$DOC_PATH" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('lockOwner',''))" 2>/dev/null || echo "")

if [ -n "$LOCK_OWNER" ]; then
    echo "Document is locked by $LOCK_OWNER — unlocking..."
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path$DOC_PATH/@lock" > /dev/null 2>&1 || true
    sleep 1
fi
echo "unlocked" > /tmp/initial_lock_state.txt

# 7. CLEAN STATE: Remove existing comments
echo "Cleaning existing comments..."
if [ -n "$DOC_UID" ]; then
    # Fetch comments
    COMMENTS_JSON=$(curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        "$NUXEO_URL/api/v1/id/$DOC_UID/@comment" 2>/dev/null || echo '{"entries":[]}')

    # Parse IDs and delete
    echo "$COMMENTS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entries', [])
    for e in entries:
        print(e.get('id', ''))
except: pass" | while read -r cid; do
        if [ -n "$cid" ]; then
            echo "  Deleting comment $cid"
            curl -s -u "$NUXEO_AUTH" -X DELETE \
                "$NUXEO_URL/api/v1/id/$DOC_UID/@comment/$cid" > /dev/null 2>&1 || true
        fi
    done
fi

# 8. Setup Browser
DOC_URL="$NUXEO_UI/#!/browse$DOC_PATH"
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

# Check if login needed
PAGE_TITLE=$(ga_x "xdotool getactivewindow getwindowname" 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

# Navigate to document
sleep 2
navigate_to "$DOC_URL"
sleep 2

# Maximize Firefox
ga_x "wmctrl -r Firefox -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="