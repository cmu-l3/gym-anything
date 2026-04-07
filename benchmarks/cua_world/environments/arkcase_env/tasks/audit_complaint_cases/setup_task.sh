#!/bin/bash
# Setup script for audit_complaint_cases
# Creates 4 specific complaint cases via API and sets up the browser

echo "=== Setting up Audit Complaint Cases Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/audit_report.txt
rm -f /tmp/ground_truth_complaints.json

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

echo "Creating audit dataset (4 complaint cases)..."
GT_FILE="/tmp/ground_truth_complaints.json"
echo "[" > "$GT_FILE"

# Define cases to create
# Format: Title|Priority
CASES=(
    "Delayed Response to Records Request|High"
    "Missing Attachments in Public Filing|Medium"
    "Urgent Data Breach Notification Failure|Expedite"
    "Minor Formatting Error in Published Report|Low"
)

FIRST=true

for case_info in "${CASES[@]}"; do
    TITLE="${case_info%|*}"
    PRIORITY="${case_info#*|}"
    
    echo "Creating case: $TITLE ($PRIORITY)"
    
    # Create via API
    # Note: Using python to parse ID safely from JSON response
    RESPONSE=$(arkcase_api POST "plugin/complaint" "{
        \"caseType\": \"GENERAL\",
        \"complaintTitle\": \"$TITLE\",
        \"details\": \"Audit task auto-generated case.\",
        \"priority\": \"$PRIORITY\",
        \"status\": \"ACTIVE\"
    }")
    
    CASE_NUMBER=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null)
    
    if [ -n "$CASE_NUMBER" ]; then
        echo "  -> Created: $CASE_NUMBER"
        
        # Append to ground truth JSON
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "$GT_FILE"
        fi
        
        # Add to JSON array
        cat >> "$GT_FILE" <<EOF
    {
        "caseNumber": "$CASE_NUMBER",
        "title": "$TITLE",
        "priority": "$PRIORITY"
    }
EOF
    else
        echo "  -> Failed to create case or parse response"
    fi
    sleep 1
done

echo "]" >> "$GT_FILE"

echo "Ground truth saved to $GT_FILE"

# ── Prepare Firefox ───────────────────────────────────────────────────────────

# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox on ArkCase login page
echo "Launching Firefox..."
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' 'https://localhost:9443/arkcase/login' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox 'https://localhost:9443/arkcase/login' &>/dev/null &" &
fi

# Wait for Firefox window
sleep 15

# Maximize and focus
focus_firefox
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
