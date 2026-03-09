#!/bin/bash
set -e
echo "=== Setting up sanitize_case_description task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Generate Random PII (Phone Number)
# Using 555-01xx range which is reserved for fiction/examples
RANDOM_SUFFIX=$(shuf -i 100-199 -n 1)
PHONE_NUMBER="202-555-0${RANDOM_SUFFIX}"
echo "$PHONE_NUMBER" > /tmp/sensitive_pii.txt
chmod 644 /tmp/sensitive_pii.txt

echo "Generated Sensitive PII: $PHONE_NUMBER"

# 3. Create the Case via ArkCase API
# We create a case with the PII in the description
DESCRIPTION="Complainant called from ${PHONE_NUMBER} on Monday regarding the delayed response to their previous FOIA request. They stated the delay is unacceptable and requested immediate escalation."
CASE_TITLE="Privacy Compliance Review - Ticket #8842"

echo "Creating case..."
# Note: ArkCase API often takes JSON. We use the helper if available or curl directly.
# Using the helper from task_utils.sh (assuming it exists based on env spec)
# Payload structure depends on ArkCase version, trying standard complaint structure.

create_foia_case "$CASE_TITLE" "$DESCRIPTION" "High"
sleep 5 # Wait for Solr indexing

# 4. Retrieve and Store Case ID
# We search for the case we just created to get its ID for verification
echo "Retrieving Case ID..."
# Search by title
SEARCH_RES=$(arkcase_api GET "plugin/complaint/search?q=Privacy+Compliance+Review" "")
# Extract ID using python (more robust json parsing than simple grep)
CASE_ID=$(echo "$SEARCH_RES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Handle search results structure
    results = data.get('searchResults', []) if isinstance(data, dict) else []
    if not results and isinstance(data, list): results = data
    
    # Find our specific case
    for item in results:
        if 'Privacy Compliance Review' in item.get('complaintTitle', ''):
            print(item.get('caseId', item.get('id', '')))
            break
except Exception as e:
    pass
")

# Fallback: if search didn't return it immediately (indexing lag), try listing recent
if [ -z "$CASE_ID" ]; then
    echo "Search failed, checking recent list..."
    LIST_RES=$(arkcase_api GET "plugin/complaint" "")
    CASE_ID=$(echo "$LIST_RES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) > 0:
        print(data[0].get('caseId', ''))
except:
    pass
")
fi

if [ -n "$CASE_ID" ]; then
    echo "$CASE_ID" > /tmp/target_case_id.txt
    chmod 644 /tmp/target_case_id.txt
    echo "Target Case ID: $CASE_ID"
else
    echo "ERROR: Failed to create or find setup case. API Response: $SEARCH_RES"
    # Create a dummy ID file to prevent total crash, but verify will fail
    echo "UNKNOWN" > /tmp/target_case_id.txt
fi

# 5. Launch Application (Firefox)
ensure_portforward
wait_for_arkcase

# Auto-login helper from task_utils
# This handles launching Firefox, navigating to login, and entering creds
if ! pgrep -f firefox > /dev/null; then
    # Launch Firefox
    SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
    if [ -n "$SNAP_PROFILE" ]; then
        su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '${ARKCASE_URL}/home.html' &"
    else
        su - ga -c "DISPLAY=:1 firefox '${ARKCASE_URL}/home.html' &"
    fi
    sleep 15
fi

# Auto-login
auto_login_arkcase "${ARKCASE_URL}/home.html"

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="