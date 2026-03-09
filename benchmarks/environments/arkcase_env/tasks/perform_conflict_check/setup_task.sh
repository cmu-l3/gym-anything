#!/bin/bash
set -e
echo "=== Setting up Conflict Check Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# ── 1. Ensure ArkCase is ready ───────────────────────────────────────────────
ensure_portforward
wait_for_arkcase

# ── 2. Generate Data ─────────────────────────────────────────────────────────
SUBJECT="Drake Antiquities"
INVESTIGATOR="Elena Fisher"

# ── 3. Create Historical Case (The Conflict) ─────────────────────────────────
echo "Creating historical case..."
OLD_CASE_TITLE="Closed Investigation: $SUBJECT - Import Audit 2022"
OLD_CASE_DETAILS="This investigation into $SUBJECT was conducted by Senior Investigator $INVESTIGATOR. The audit found minor discrepancies in the import logs from Q3 2022. Case closed with warning."

# Create via API (Priority Low, Closed implies historical context in description)
OLD_CASE_RESP=$(create_foia_case "$OLD_CASE_TITLE" "$OLD_CASE_DETAILS" "Low")
OLD_CASE_ID=$(echo "$OLD_CASE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

# Retry logic if ID not captured
if [ -z "$OLD_CASE_ID" ]; then
    sleep 5
    OLD_CASE_ID=$(arkcase_api GET "plugin/complaint" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['caseNumber'])" 2>/dev/null)
fi

echo "Created Historical Case: $OLD_CASE_ID"

# ── 4. Create New Case (The Active One) ──────────────────────────────────────
echo "Creating new active case..."
sleep 2
NEW_CASE_TITLE="New Complaint: $SUBJECT - Unlicensed Artifacts"
NEW_CASE_DETAILS="Received anonymous tip regarding $SUBJECT selling unlicensed artifacts. Assigning initial review."

NEW_CASE_RESP=$(create_foia_case "$NEW_CASE_TITLE" "$NEW_CASE_DETAILS" "High")
NEW_CASE_ID=$(echo "$NEW_CASE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

# Ensure we got a different ID
if [ -z "$NEW_CASE_ID" ] || [ "$NEW_CASE_ID" == "$OLD_CASE_ID" ]; then
    sleep 5
    # Fetch list and pick the one that isn't the old one
    NEW_CASE_ID=$(arkcase_api GET "plugin/complaint" | python3 -c "import sys, json; 
data=json.load(sys.stdin); 
old='$OLD_CASE_ID';
res=[c['caseNumber'] for c in data if c['caseNumber'] != old];
print(res[0] if res else '')" 2>/dev/null)
fi

echo "Created New Case: $NEW_CASE_ID"

# ── 5. Save Metadata for Export/Verify ───────────────────────────────────────
# We save this to a JSON file so export_result.sh can read it later
cat > /tmp/conflict_task_data.json << EOF
{
    "old_case_id": "$OLD_CASE_ID",
    "new_case_id": "$NEW_CASE_ID",
    "subject": "$SUBJECT",
    "investigator": "$INVESTIGATOR"
}
EOF

# ── 6. Setup UI State ────────────────────────────────────────────────────────
# Open Firefox to the Dashboard so agent starts fresh
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"

# Auto-login
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Old Case: $OLD_CASE_ID"
echo "New Case: $NEW_CASE_ID"