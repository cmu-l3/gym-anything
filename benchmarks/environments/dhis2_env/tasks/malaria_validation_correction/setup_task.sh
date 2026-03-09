#!/bin/bash
# Setup script for Malaria Validation & Correction task

echo "=== Setting up Malaria Validation Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Wait for DHIS2
echo "Checking DHIS2 readiness..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 30
fi

# 2. Inject Data Error
echo "Injecting data error..."

# Get IDs for Data Elements and Org Unit
# We use ILIKE for case-insensitive matching to be robust
TESTED_ID=$(dhis2_query "SELECT uid FROM dataelement WHERE name ILIKE 'Malaria RDT tested' LIMIT 1" | tr -d ' ')
POSITIVE_ID=$(dhis2_query "SELECT uid FROM dataelement WHERE name ILIKE 'Malaria RDT positive' LIMIT 1" | tr -d ' ')
ORG_ID=$(dhis2_query "SELECT uid FROM organisationunit WHERE name ILIKE 'Ngelehun CHC' LIMIT 1" | tr -d ' ')
COC_ID=$(dhis2_query "SELECT uid FROM categoryoptioncombo WHERE name='default' LIMIT 1" | tr -d ' ')

if [ -z "$TESTED_ID" ] || [ -z "$POSITIVE_ID" ] || [ -z "$ORG_ID" ]; then
    echo "ERROR: Could not find required metadata UIDs. setup failed."
    echo "Tested: $TESTED_ID, Positive: $POSITIVE_ID, Org: $ORG_ID"
    # Try to continue, but task might be broken
fi

echo "Metadata UIDs: Tested=$TESTED_ID, Positive=$POSITIVE_ID, Org=$ORG_ID"

# IDs for SQL insertion (need numeric IDs for data value table usually, or use API)
# Using API is safer for data injection to ensure integrity
echo "Injecting via API..."

# Create payload: Positive > Tested (250 > 120)
# Period: 202301
cat > /tmp/data_injection.json << EOF
{
  "dataValues": [
    { "dataElement": "$TESTED_ID", "period": "202301", "orgUnit": "$ORG_ID", "value": "120" },
    { "dataElement": "$POSITIVE_ID", "period": "202301", "orgUnit": "$ORG_ID", "value": "250" }
  ]
}
EOF

# Post data
curl -s -u admin:district -H "Content-Type: application/json" -X POST -d @/tmp/data_injection.json "http://localhost:8080/api/dataValueSets" > /dev/null

# Backdate the data values in DB so we can detect agent updates later
# (API sets lastupdated to NOW, we want it in the past)
echo "Backdating injected data..."
dhis2_query "
UPDATE datavalue 
SET lastupdated = '2023-01-01 12:00:00' 
WHERE periodid = (SELECT periodid FROM period WHERE iso = '202301')
AND sourceid = (SELECT organisationunitid FROM organisationunit WHERE uid = '$ORG_ID');
"

# 3. Clean up any existing validation rules with similar names
echo "Cleaning old rules..."
dhis2_query "DELETE FROM validationrule WHERE name ILIKE '%Positive vs Tested%';"

# 4. Start Firefox
echo "Starting Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 8
fi

# Wait and Focus
wait_for_window "firefox" 20
focus_window "$(get_firefox_window_id)"
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Record Start Time
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Error injected: Tested=120, Positive=250 (Invalid)"