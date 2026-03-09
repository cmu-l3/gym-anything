#!/bin/bash
set -e
echo "=== Setting up create_saved_case_filter task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 1. GENERATE DATA
# We need specific High and Low priority cases to verify the filter works.
# We will store the resulting Case Numbers for verification.

echo "Generating High Priority cases..."
# Case 1
RESP=$(create_foia_case "Imminent Structural Failure at Warehouse 4" "Report of cracking beams and water damage at federal storage facility." "High")
ID1=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

# Case 2
RESP=$(create_foia_case "Whistleblower: Gross Mismanagement of Funds" "Internal report regarding allocation of safety grants." "High")
ID2=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

# Case 3
RESP=$(create_foia_case "Critical Patient Safety Violation" "VA hospital protocol breach resulting in patient risk." "High")
ID3=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

echo "High Priority IDs: $ID1, $ID2, $ID3"
echo "$ID1" > /tmp/ground_truth_high.txt
echo "$ID2" >> /tmp/ground_truth_high.txt
echo "$ID3" >> /tmp/ground_truth_high.txt

echo "Generating Low Priority cases..."
# Case 4
RESP=$(create_foia_case "Suggestion for Cafeteria Vending Machines" "Request for more healthy snack options." "Low")
ID4=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

# Case 5
RESP=$(create_foia_case "Typo in Monthly Newsletter" "Spelling error on page 4 of the internal newsletter." "Low")
ID5=$(echo "$RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null || echo "")

echo "Low Priority IDs: $ID4, $ID5"
echo "$ID4" > /tmp/ground_truth_low.txt
echo "$ID5" >> /tmp/ground_truth_low.txt

# 2. PREPARE BROWSER
# Kill existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
echo "Launching Firefox..."
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"

# Auto-login
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="