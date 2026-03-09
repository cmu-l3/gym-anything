#!/bin/bash
set -e
echo "=== Setting up add_web_reference task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure port-forward is active and ArkCase is reachable
ensure_portforward
wait_for_arkcase

echo "=== Creating Complaint Case ==="
# Create a unique complaint case for this run
CASE_TITLE="Community Park Vandalism"
CASE_DESC="Investigation into graffiti and equipment damage at the north entrance. Witnesses reported seeing suspects at 10 PM."

# Check if case already exists (from previous run) to avoid duplicates
# Note: Using python to parse JSON response safely
EXISTING_CASES=$(arkcase_api GET "plugin/complaint?size=100" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('searchResults', [])
    count = sum(1 for c in results if c.get('complaintTitle') == '$CASE_TITLE')
    print(count)
except:
    print(0)
")

if [ "$EXISTING_CASES" -eq "0" ]; then
    echo "Creating new case..."
    create_foia_case "$CASE_TITLE" "$CASE_DESC" "High"
else
    echo "Case '$CASE_TITLE' already exists."
fi

# Store the Case ID for the export script to use later
# We fetch it again to be sure
arkcase_api GET "plugin/complaint?size=100" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('searchResults', [])
    for c in results:
        if c.get('complaintTitle') == '$CASE_TITLE':
            print(c.get('complaintId', c.get('id')))
            break
except:
    pass
" > /tmp/target_case_id.txt

echo "Target Case ID: $(cat /tmp/target_case_id.txt)"

# Ensure Firefox is open and logged in
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
auto_login_arkcase

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="