#!/bin/bash
set -e
echo "=== Setting up configure_vocabulary_entries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Nuxeo to be responsive
wait_for_nuxeo 180

echo "Preparing initial state..."

# 1. Ensure 'Annual Report 2023' exists
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    echo "Creating Annual Report 2023..."
    # Copy real PDF if available
    PDF_SOURCE="/workspace/data/annual_report_2023.pdf"
    [ -f "$PDF_SOURCE" ] || PDF_SOURCE="/home/ga/nuxeo/data/Annual_Report_2023.pdf"
    
    if [ -f "$PDF_SOURCE" ]; then
        # Simple create without upload if upload logic is complex, 
        # but let's try to use the PDF if we can, or just create a File doc metadata
        # For this task, metadata is the key, content is secondary.
        # We'll create a placeholder File doc to be safe and fast.
        create_doc "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" \
            "Annual Report 2023" "Financial report" > /dev/null
    else
        create_doc "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" \
            "Annual Report 2023" "Financial report" > /dev/null
    fi
fi

# 2. Reset the document's 'nature' field (clear it)
echo "Clearing nature field on Annual Report 2023..."
curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    -X PUT "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023" \
    -d '{"entity-type":"document","properties":{"dc:nature":null}}' > /dev/null

# 3. Clean up vocabulary: Ensure target entries do NOT exist
echo "Cleaning vocabulary 'nature'..."
TARGET_IDS=("memorandum" "policy_brief" "regulatory_filing")

for id in "${TARGET_IDS[@]}"; do
    # Check if entry exists
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
        "$NUXEO_URL/api/v1/directory/nature/$id")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Deleting existing vocabulary entry: $id"
        curl -s -u "$NUXEO_AUTH" -X DELETE \
            "$NUXEO_URL/api/v1/directory/nature/$id" > /dev/null || true
    fi
done

# 4. Record initial count of nature vocabulary (for reference)
INITIAL_VOCAB_COUNT=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/directory/nature" | \
    python3 -c "import sys, json; print(len(json.load(sys.stdin).get('entries', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_VOCAB_COUNT" > /tmp/initial_vocab_count.txt

# 5. Launch Firefox and login
echo "Launching Firefox..."
# Start fresh
pkill -f firefox || true

# Open Nuxeo URL
# We open the home page. The agent must navigate to Administration manually.
open_nuxeo_url "$NUXEO_URL/login.jsp" 10

# Perform login automation if needed
# (Check window title to see if we are on login page)
sleep 5
PAGE_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if echo "$PAGE_TITLE" | grep -qi "login"; then
    nuxeo_login
fi

# Ensure window is maximized for the agent
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="