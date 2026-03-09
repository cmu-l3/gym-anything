#!/bin/bash
set -e
echo "=== Setting up create_case_task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure port-forward is active for API calls
ensure_portforward

# Wait for ArkCase to be accessible
wait_for_arkcase

# ── 1. Create the complaint case via REST API ────────────────────────────────
echo "Creating complaint case via API..."

# Create a unique case title to avoid collision if task runs multiple times
CASE_TITLE="Henderson v. DOJ – FOIA #2025-0472"
CASE_DETAILS="Freedom of Information Act request from James Henderson seeking records related to DOJ internal policy memoranda on immigration enforcement discretion from January 2024 through December 2024."

CASE_PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$CASE_TITLE",
    "details": "$CASE_DETAILS",
    "priority": "High",
    "status": "ACTIVE"
}
EOF
)

CASE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$CASE_PAYLOAD" \
    "${ARKCASE_URL}/api/v1/plugin/complaint" 2>/dev/null || echo "{}")

echo "Case creation response: $CASE_RESPONSE"

# Extract case ID/number for verification
CASE_NUMBER=$(echo "$CASE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintNumber', d.get('caseNumber', '')))" 2>/dev/null || echo "")

if [ -z "$CASE_NUMBER" ]; then
    echo "WARNING: Failed to create case via API. Agent may need to search generic terms."
    # Attempt to find if it already exists
    SEARCH_RESP=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" "${ARKCASE_URL}/api/v1/plugin/search/advancedSearch?query=complaintTitle:Henderson" 2>/dev/null)
    CASE_NUMBER=$(echo "$SEARCH_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); docs=d.get('response',{}).get('docs',[]); print(docs[0].get('caseNumber','') if docs else '')" 2>/dev/null || echo "")
fi

echo "Target Case Number: $CASE_NUMBER"
echo "$CASE_NUMBER" > /tmp/parent_case_number.txt

# ── 2. Record initial task count for the case ────────────────────────────────
INITIAL_TASKS=0
if [ -n "$CASE_NUMBER" ]; then
    sleep 2 # Allow indexing
    INITIAL_TASKS=$(curl -sk \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/search/advancedSearch?query=object_type_s:TASK+AND+parent_number_lcs:${CASE_NUMBER}&start=0&rows=0" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',{}).get('numFound', 0))" 2>/dev/null || echo "0")
fi
echo "$INITIAL_TASKS" > /tmp/initial_task_count.txt
echo "Initial task count for case $CASE_NUMBER: $INITIAL_TASKS"

# ── 3. Open Firefox on the ArkCase login page ────────────────────────────────
echo "Launching Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/' &" &
sleep 10

# Handle SSL warning if present
handle_ssl_warning
sleep 5

# Maximize Firefox
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="