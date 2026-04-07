#!/bin/bash
echo "=== Setting up search_case_by_phrase task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate unique identifier for this run to prevent finding old/stale cases
RUN_ID=$(cat /proc/sys/kernel/random/uuid | cut -c1-8)
SEARCH_PHRASE="Project Blue Sky $RUN_ID"
echo "Generated search phrase: $SEARCH_PHRASE"

# 2. Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 3. Create the target case via API
# We put the search phrase in the 'details' field which is indexed by Solr
echo "Creating target case..."
CASE_TITLE="Internal Investigation - Unspecified Matter"
CASE_DETAILS="CONFIDENTIAL: This case involves sensitive information regarding $SEARCH_PHRASE. Handle with extreme care. Referenced in briefing 42."

RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"High\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

# Extract Case ID
CASE_ID=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # API might return 'complaintId' or just 'id' depending on version
    print(d.get('complaintId', d.get('caseId', d.get('id', ''))))
except:
    print('')
" 2>/dev/null || echo "")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case. API Response: $RESPONSE"
    # Fallback for manual testing or if API fails
    CASE_ID="MANUAL_CHECK_NEEDED"
else
    echo "Created target case: $CASE_ID"
fi

# Save Ground Truth (Hidden from agent)
echo "$CASE_ID" > /tmp/ground_truth_id.txt
echo "$SEARCH_PHRASE" > /tmp/search_phrase.txt
chmod 600 /tmp/ground_truth_id.txt

# 4. Provide the search phrase to the agent via a sticky note on desktop
# or just a file in Documents
echo "Investigator," > /home/ga/Documents/mission_brief.txt
echo "" >> /home/ga/Documents/mission_brief.txt
echo "We need to find a case related to: '$SEARCH_PHRASE'" >> /home/ga/Documents/mission_brief.txt
echo "" >> /home/ga/Documents/mission_brief.txt
echo "Use the Global Search to find it and record the Case ID." >> /home/ga/Documents/mission_brief.txt
chown ga:ga /home/ga/Documents/mission_brief.txt

# 5. Launch Firefox to the Dashboard (standard start state)
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 4
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox
echo "Launching Firefox..."
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
sleep 10
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target Case ID: $CASE_ID"
echo "Search Phrase: $SEARCH_PHRASE"

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
