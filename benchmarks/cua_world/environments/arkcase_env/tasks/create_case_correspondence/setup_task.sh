#!/bin/bash
set -e
echo "=== Setting up create_case_correspondence task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure port forwarding is active for API access
ensure_portforward
wait_for_arkcase

# 1. Create the target Complaint Case via API
echo "Creating test complaint case..."
CASE_TITLE="FOIA-Correspondence-Test-2025"
CASE_DETAILS="Request for public records related to environmental impact assessments conducted in fiscal year 2024. Requester is a journalist from the City Tribune investigating compliance with state environmental regulations."

# Create case
CASE_RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

# Extract Case ID
CASE_ID=$(echo "$CASE_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Handle different possible ID fields depending on ArkCase version/config
    print(d.get('complaintId', d.get('id', d.get('caseId', ''))))
except:
    print('')
" 2>/dev/null || echo "")

if [ -n "$CASE_ID" ]; then
    echo "$CASE_ID" > /tmp/target_case_id.txt
    echo "Created case '$CASE_TITLE' with ID: $CASE_ID"
else
    echo "WARNING: Failed to create case via API. Response: $CASE_RESPONSE"
    # Fallback: Agent might still find it if it was created in a previous run, 
    # or fail if not. We'll proceed with setup.
fi

# 2. Record initial correspondence count for this case (should be 0)
if [ -n "$CASE_ID" ]; then
    INITIAL_CORR=$(arkcase_api GET "plugin/complaint/${CASE_ID}/correspondence" 2>/dev/null || echo "[]")
    INITIAL_COUNT=$(echo "$INITIAL_CORR" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_corr_count.txt
fi

# 3. Setup Browser
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html#!/dashboard"
sleep 5
handle_ssl_warning
sleep 2

# Auto-login to Dashboard
auto_login_arkcase "${ARKCASE_URL}/home.html#!/dashboard"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Case: $CASE_TITLE (ID: $CASE_ID)"