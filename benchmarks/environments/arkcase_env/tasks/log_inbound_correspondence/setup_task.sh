#!/bin/bash
set -e
echo "=== Setting up log_inbound_correspondence task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 3. Create the target Complaint Case via API
CASE_TITLE="Noise Complaint - Downtown Construction"
CASE_DESC="Resident reports loud machinery operating outside permitted hours at Main St & 4th Ave."

echo "Creating case: $CASE_TITLE..."
# Create case and capture the full JSON response
RESPONSE=$(create_foia_case "$CASE_TITLE" "$CASE_DESC" "High")

# Extract Case ID (technical ID) and Case Number (human readable)
# Depending on API version, ID might be in 'id', 'complaintId', or 'caseId'
CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Try common ID fields
    print(d.get('id') or d.get('complaintId') or d.get('caseId') or '')
except:
    print('')
")

if [ -z "$CASE_ID" ]; then
    # Fallback: Try to find it via search if creation return was ambiguous
    echo "Searching for case ID..."
    sleep 2
    SEARCH_RES=$(arkcase_api GET "plugin/complaint" | jq -r ".[] | select(.complaintTitle == \"$CASE_TITLE\") | .id" | head -1)
    CASE_ID="$SEARCH_RES"
fi

if [ -z "$CASE_ID" ]; then
    echo "CRITICAL ERROR: Failed to create or locate case."
    exit 1
fi

echo "Target Case ID: $CASE_ID"
echo "$CASE_ID" > /tmp/target_case_id.txt

# 4. Record initial correspondence count
# Check standard endpoints for correspondence/communications
INITIAL_CORR=$(arkcase_api GET "plugin/complaint/${CASE_ID}/correspondence" 2>/dev/null || echo "[]")
INITIAL_COUNT=$(echo "$INITIAL_CORR" | jq '. | length' 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_corr_count.txt
echo "Initial correspondence count: $INITIAL_COUNT"

# 5. Create the .eml file (Realistic Data)
mkdir -p /home/ga/Documents
cat <<EOF > /home/ga/Documents/evidence_email.eml
From: "Alice Neighbor" <alice.neighbor@example.com>
To: "Public Works Dept" <publicworks@city.gov>
Subject: Urgent: Construction Violation Report
Date: Wed, 28 Feb 2026 08:15:00 -0500
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

To Whom It May Concern,

I am writing to formally report a violation of the city noise ordinance.
The construction crew at the 'Downtown Lofts' site (Main St & 4th Ave)
has been operating heavy jackhammers starting at 5:30 AM for the past
three days.

The posted permit clearly states that work cannot begin before 7:00 AM.
I have attached audio recordings in a separate email. Please investigate
immediately as this is disrupting the entire neighborhood.

Regards,
Alice Neighbor
125 Main St, Apt 4B
Phone: 555-0199
EOF

chown ga:ga /home/ga/Documents/evidence_email.eml
chmod 644 /home/ga/Documents/evidence_email.eml

# 6. Launch Firefox and Login
# Ensure clean state
pkill -f firefox 2>/dev/null || true
sleep 2

ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
auto_login_arkcase "${ARKCASE_URL}/home.html"

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="