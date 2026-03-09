#!/bin/bash
set -e
echo "=== Setting up Internal Affairs Check Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for ArkCase to be ready
wait_for_arkcase
ensure_portforward

# 2. Generate Random Subject Name (Realism & Anti-Gaming)
FIRST_NAMES=("Elena" "Marcus" "Sarah" "David" "Jessica" "Robert" "Linda")
LAST_NAMES=("Fisher" "Chen" "Rodriguez" "Smith" "Patel" "Mbatha" "Kowalski")
RAND_FIRST=${FIRST_NAMES[$RANDOM % ${#FIRST_NAMES[@]}]}
RAND_LAST=${LAST_NAMES[$RANDOM % ${#LAST_NAMES[@]}]}
SUBJECT_NAME="$RAND_FIRST $RAND_LAST"
SUBJECT_EMAIL="${RAND_FIRST}.${RAND_LAST}@arkcase.com"
SUBJECT_EMAIL=$(echo "$SUBJECT_EMAIL" | tr '[:upper:]' '[:lower:]')

echo "Generated Subject: $SUBJECT_NAME ($SUBJECT_EMAIL)"

# 3. Create the Person Record (The Employee) via API
echo "Creating Person record..."
# We use the generic complaints/participants API or specific person API depending on exact ArkCase version
# For this task, we assume a standard structure. If specific API fails, we rely on search mocking or existing data,
# but here we attempt real creation.
PERSON_PAYLOAD=$(cat <<EOF
{
    "firstName": "$RAND_FIRST",
    "lastName": "$RAND_LAST",
    "email": "$SUBJECT_EMAIL",
    "businessPhone": "555-0199",
    "objectType": "PERSON"
}
EOF
)
# Note: Actual endpoint might vary; suppressing error to avoid crash if API differs slightly
arkcase_api POST "plugin/people/save" "$PERSON_PAYLOAD" 2>/dev/null || true

# 4. Create the Complaint Case via API
echo "Creating Complaint Case..."
CASE_TITLE="Allegation of Policy Violation - $RAND_LAST"
CASE_DESC="We have received a credible report regarding $SUBJECT_NAME involving the misuse of departmental travel funds during the Q3 conference. Please investigate immediately."

# Create case with "Medium" priority initially
# Function create_foia_case defined in task_utils.sh
create_foia_case "$CASE_TITLE" "$CASE_DESC" "Medium"

# 5. Retrieve the Case Number
sleep 8 # Allow for indexing
SEARCH_RES=$(arkcase_api GET "search/search?q=$RAND_LAST&type=COMPLAINT")

# Extract Case Number and ID using python/jq
CASE_INFO=$(echo "$SEARCH_RES" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    res = data.get('searchResults', [])[0]
    print(json.dumps({'number': res.get('caseNumber'), 'id': res.get('id')}))
except:
    print('{}')
")

CASE_NUMBER=$(echo "$CASE_INFO" | grep -o '"number": *"[^"]*"' | cut -d'"' -f4)
CASE_ID=$(echo "$CASE_INFO" | grep -o '"id": *"[^"]*"' | cut -d'"' -f4)

if [ -z "$CASE_NUMBER" ]; then
    echo "WARNING: Could not retrieve case number from API. Using fallback search instruction."
    CASE_NUMBER="SEARCH FOR: '$CASE_TITLE'"
    CASE_ID="UNKNOWN"
fi

echo "Created Case: $CASE_NUMBER (ID: $CASE_ID)"

# 6. Save Task Data for Agent
echo "Target Case Number: $CASE_NUMBER" > /home/ga/task_data.txt
chown ga:ga /home/ga/task_data.txt

# 7. Store Ground Truth for Export Script (Hidden from agent)
mkdir -p /var/lib/arkcase/ground_truth
cat > /var/lib/arkcase/ground_truth/info.json <<EOF
{
    "case_id": "$CASE_ID",
    "case_number": "$CASE_NUMBER",
    "subject_name": "$SUBJECT_NAME",
    "expected_priority": "High",
    "keyword": "Internal Affairs"
}
EOF
chmod 600 /var/lib/arkcase/ground_truth/info.json

# 8. Launch Firefox and Login
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="