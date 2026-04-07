#!/bin/bash
# Setup: Create a user, create a complaint case, open Firefox to ArkCase
set -e

echo "=== Setting up reassign_complaint_case task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# ── 1. Ensure port-forward and ArkCase accessibility ─────────────────────────
ensure_portforward
wait_for_arkcase

echo "ArkCase is accessible."

# ── 2. Create user 'sally-acm' in LDAP (Samba AD) ────────────────────────────
# ArkCase uses Samba AD as its LDAP backend. We create the user there so they appear in pickers.
echo "Creating user sally-acm in Samba AD..."

LDAP_POD=$(KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get pods -n arkcase \
    --no-headers 2>/dev/null | grep ldap | grep Running | awk '{print $1}' | head -1)

if [ -n "$LDAP_POD" ]; then
    echo "Found LDAP pod: $LDAP_POD"

    # Create user sally-acm with samba-tool
    # We ignore error if user already exists
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl exec -n arkcase "$LDAP_POD" -- \
        samba-tool user create sally-acm 'SallyAcm@2024!' \
        --given-name="Sally" \
        --surname="Acm" \
        --mail-address="sally-acm@dev.arkcase.com" \
        2>/dev/null || echo "User sally-acm creation skipped (may exist)"

    # Add user to ACM groups so they appear in ArkCase user lists
    # Using common ArkCase groups
    for GROUP in "ACM_INVESTIGATOR_DEV" "ACM_ADMINISTRATOR_DEV"; do
        KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl exec -n arkcase "$LDAP_POD" -- \
            samba-tool group addmembers "$GROUP" sally-acm \
            2>/dev/null || echo "Group add skipped for $GROUP"
    done
else
    echo "WARNING: LDAP pod not found, skipping backend user creation (task may fail if user missing)"
fi

echo "User sally-acm setup complete."

# ── 3. Create a complaint case via REST API ───────────────────────────────────
echo "Creating complaint case..."

# Create the complaint
COMPLAINT_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${ARKCASE_URL}/api/v1/plugin/complaint" \
    -d '{
        "complaintTitle": "Public Records Request - Water Quality Data",
        "details": "A citizen has requested copies of all water quality testing reports from the municipal water treatment facility for the period January 2023 through December 2023. This is a high-priority FOIA request due to the 10-business-day statutory response deadline.",
        "priority": "High",
        "caseType": "GENERAL"
    }' 2>/dev/null)

# Extract case number and ID using python for reliability
CASE_NUMBER=$(echo "$COMPLAINT_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Check standard ArkCase response fields
    print(data.get('complaintNumber') or data.get('caseNumber') or data.get('id', ''))
except:
    pass
" 2>/dev/null)

CASE_ID=$(echo "$COMPLAINT_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # The API usually returns the object ID in 'id' or 'complaintId'
    print(data.get('complaintId') or data.get('id', ''))
except:
    pass
" 2>/dev/null)

if [ -z "$CASE_NUMBER" ]; then
    echo "ERROR: Failed to create case. Response: $COMPLAINT_RESPONSE"
    # Fallback for resiliency: try to find an existing one
    CASE_NUMBER="COMP-2024-001" # Fake fallback, agent will likely fail but env won't crash
    CASE_ID="unknown"
fi

echo "Created Case: $CASE_NUMBER (ID: $CASE_ID)"

# Save case identifiers for the agent and verifier
echo "$CASE_NUMBER" > /tmp/complaint_case_number.txt
echo "$CASE_ID" > /tmp/complaint_case_id.txt

# Make case number file readable by agent
chmod 644 /tmp/complaint_case_number.txt
chown ga:ga /tmp/complaint_case_number.txt 2>/dev/null || true

# ── 4. Launch Firefox and navigate to ArkCase ────────────────────────────────
echo "Launching Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 3

# Start Firefox
# We start at the complaints module directly
TARGET_URL="https://localhost:9443/arkcase/home.html#!/complaints"

# Launch in background
su - ga -c "DISPLAY=:1 firefox --no-remote '$TARGET_URL' &" &
sleep 15

# Handle potential SSL warnings
handle_ssl_warning
sleep 5

# Focus and maximize
focus_firefox
maximize_firefox
sleep 2

# Auto-login using the utility function
auto_login_arkcase "$TARGET_URL"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
