#!/bin/bash
# Setup script for verify_evidence_chain_of_custody
set -e

echo "=== Setting up Verify Evidence Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 2. Generate Evidence Data
mkdir -p /home/ga/evidence
EVIDENCE_FILE="/home/ga/evidence/server_access_logs.txt"

# Generate realistic Apache logs
echo "Generating log data..."
cat > "$EVIDENCE_FILE" << EOF
192.168.1.105 - - [14/May/2024:10:05:01 -0500] "GET /index.html HTTP/1.1" 200 1024
192.168.1.105 - - [14/May/2024:10:05:02 -0500] "GET /css/style.css HTTP/1.1" 200 512
10.0.0.45 - - [14/May/2024:10:06:15 -0500] "POST /login HTTP/1.1" 302 0
10.0.0.45 - - [14/May/2024:10:06:16 -0500] "GET /dashboard HTTP/1.1" 200 4096
172.16.0.22 - - [14/May/2024:10:15:33 -0500] "GET /api/v1/users HTTP/1.1" 403 45
192.168.1.105 - - [14/May/2024:10:20:01 -0500] "GET /images/logo.png HTTP/1.1" 200 2048
EOF

# Pad with some random data to ensure uniqueness
head -c 128 /dev/urandom | base64 >> "$EVIDENCE_FILE"

# 3. Calculate Original Hash (The "Golden" Record)
ORIGINAL_HASH=$(sha256sum "$EVIDENCE_FILE" | awk '{print $1}')
echo "Original Hash: $ORIGINAL_HASH"

# 4. Determine if file is compromised (50/50 chance)
# Use date nanoseconds to get random 0 or 1
if [ $(( $(date +%N) % 2 )) -eq 0 ]; then
    STATUS="COMPROMISED"
    echo "Scenario: Evidence is COMPROMISED"
    # Modify the file
    echo "# UNAUTHORIZED MODIFICATION $(date)" >> "$EVIDENCE_FILE"
else
    STATUS="INTACT"
    echo "Scenario: Evidence is INTACT"
fi

# Calculate Actual Hash (Current state of file on disk)
ACTUAL_HASH=$(sha256sum "$EVIDENCE_FILE" | awk '{print $1}')
echo "Actual Hash:   $ACTUAL_HASH"

# 5. Create ArkCase Complaint Case via API
CASE_TITLE="Forensic Audit - Server Logs - Case #$(date +%s)"
CASE_DETAILS="Chain of custody verification for seized server logs. Reference: INC-$(date +%Y%m%d)-99."

echo "Creating ArkCase complaint..."
# Using helper from task_utils.sh or direct curl
# Note: ArkCase API often returns the object. We need to extract the ID.
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"$CASE_TITLE\",
    \"details\": \"$CASE_DETAILS\",
    \"priority\": \"High\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null)

# Extract Case ID (Complaint Number)
# The API returns JSON with "complaintId" or "id"
CASE_NUMBER=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintNumber', 'UNKNOWN'))" 2>/dev/null || echo "")

# Fallback if parsing failed
if [ -z "$CASE_NUMBER" ] || [ "$CASE_NUMBER" == "UNKNOWN" ]; then
    # Try getting 'id' or just use a fixed ID if API fails (simulated fallback not ideal but safe)
    CASE_NUMBER="2024-AUDIT-FAIL"
    echo "WARNING: Failed to parse case number from API response. Response: $RESPONSE"
    # In a real env, we'd retry or fail. For robustness, we assume it worked or use a fallback if the env is flaky.
    # Let's try to list recent complaints to find it.
    SEARCH_RESP=$(arkcase_api GET "plugin/complaint?page=1&size=1" 2>/dev/null)
    CASE_NUMBER=$(echo "$SEARCH_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin)[0].get('complaintNumber'))" 2>/dev/null || echo "")
fi

echo "Created Case: $CASE_NUMBER"
echo "$CASE_NUMBER" > /home/ga/case_to_audit.txt
chmod 644 /home/ga/case_to_audit.txt

# Get internal ID for adding note (often different from Case Number)
CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null)

# 6. Add Chain of Custody Note
# Note: ArkCase API for notes usually requires the parent object ID
if [ -n "$CASE_ID" ]; then
    NOTE_TEXT="Chain of Custody Record: Initial SHA256 hash: $ORIGINAL_HASH. Seized by Agent Smith."
    echo "Adding note to case $CASE_ID..."
    arkcase_api POST "plugin/complaint/$CASE_ID/note" "{
        \"note\": \"$NOTE_TEXT\"
    }" > /dev/null 2>&1 || echo "Note creation warning"
else
    echo "ERROR: Could not get Case ID to add note."
fi

# 7. Save Ground Truth for Verifier (Hidden)
mkdir -p /var/lib/arkcase/ground_truth
cat > /var/lib/arkcase/ground_truth/evidence_audit.json << EOF
{
    "case_number": "$CASE_NUMBER",
    "status": "$STATUS",
    "recorded_hash": "$ORIGINAL_HASH",
    "actual_hash": "$ACTUAL_HASH",
    "filename": "server_access_logs.txt"
}
EOF
chmod 644 /var/lib/arkcase/ground_truth/evidence_audit.json

# 8. Setup Browser (Login and sit at Dashboard)
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Check for Snap profile
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
LOGIN_URL="https://localhost:9443/arkcase/login"

if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$LOGIN_URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$LOGIN_URL' &>/dev/null &" &
fi

# Wait for load and perform auto-login
wait_for_arkcase
sleep 15
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="
echo "Case Number: $CASE_NUMBER"
echo "Evidence File: $EVIDENCE_FILE"