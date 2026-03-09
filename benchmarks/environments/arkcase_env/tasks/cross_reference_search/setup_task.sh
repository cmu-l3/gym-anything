#!/bin/bash
set -e
echo "=== Setting up Cross-Reference Search Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 3. Generate Unique Data to prevent guessing from previous runs
SUFFIX=$(date +%s | tail -c 4)
ORG_NAME="Falcon Industries $SUFFIX"
ORG_WEB="https://www.falcon-ind-$SUFFIX.com"

PERSON_FIRST="John"
PERSON_LAST="Falcone-$SUFFIX"
PERSON_EMAIL="j.falcone.$SUFFIX@example.com"

CASE_TITLE="Falcon Project Security Breach $SUFFIX"

echo "Generated Data:"
echo "  Org: $ORG_NAME ($ORG_WEB)"
echo "  Person: $PERSON_FIRST $PERSON_LAST ($PERSON_EMAIL)"
echo "  Case: $CASE_TITLE"

# 4. Create Organization via API
# Payload adapted for standard ArkCase organization plugin
echo "Creating Organization..."
ORG_PAYLOAD=$(cat <<EOF
{
  "name": "$ORG_NAME",
  "website": "$ORG_WEB",
  "organizationType": "COMMERCIAL",
  "active": true
}
EOF
)
arkcase_api POST "plugin/organization" "$ORG_PAYLOAD" > /tmp/org_response.json 2>/dev/null || true

# 5. Create Person via API
echo "Creating Person..."
PERSON_PAYLOAD=$(cat <<EOF
{
  "firstName": "$PERSON_FIRST",
  "lastName": "$PERSON_LAST",
  "email": "$PERSON_EMAIL",
  "businessPhone": "555-0199",
  "active": true
}
EOF
)
arkcase_api POST "plugin/person" "$PERSON_PAYLOAD" > /tmp/person_response.json 2>/dev/null || true

# 6. Create Complaint Case via API (using helper)
echo "Creating Case..."
# We need to capture the response to get the Case Number (formatted ID)
# The create_foia_case helper doesn't output JSON to stdout, so we construct the raw call here
CASE_PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$CASE_TITLE",
    "details": "Investigation into unauthorized data egress regarding Project Falcon.",
    "priority": "High",
    "status": "ACTIVE"
}
EOF
)
arkcase_api POST "plugin/complaint" "$CASE_PAYLOAD" > /tmp/case_response.json 2>/dev/null || true

# Extract Case Number (e.g., "20250101-005") from response
# ArkCase API usually returns 'caseNumber' or 'id' (database ID). 
# We need the human-readable case number displayed in UI.
# In standard ArkCase, 'caseNumber' is the field.
CASE_NUM=$(jq -r '.caseNumber // .id' /tmp/case_response.json)

echo "Created Case Number: $CASE_NUM"

# 7. Save Ground Truth (Hidden from Agent)
mkdir -p /home/ga/.hidden
cat <<EOF > /home/ga/.hidden/ground_truth.json
{
  "organization_website": "$ORG_WEB",
  "person_email": "$PERSON_EMAIL",
  "case_number": "$CASE_NUM"
}
EOF
chmod 600 /home/ga/.hidden/ground_truth.json

# 8. Wait for Solr/Elasticsearch Indexing
# Search tasks fail if we don't wait for the indexer to pick up new records
echo "Waiting 20s for search index update..."
sleep 20

# 9. Launch Firefox
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"

# 10. Auto-login
# (Assuming Firefox is already running from ensure_firefox_on_arkcase)
auto_login_arkcase "${ARKCASE_URL}/home.html"

# 11. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="