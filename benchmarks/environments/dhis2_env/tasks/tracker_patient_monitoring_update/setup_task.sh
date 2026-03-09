#!/bin/bash
# Setup script for Tracker Patient Monitoring Update task

echo "=== Setting up Tracker Patient Monitoring Task ==="

source /workspace/scripts/task_utils.sh

# Function definitions for API interaction
dhis2_api_post() {
    local endpoint="$1"
    local data="$2"
    curl -s -u admin:district -X POST -H "Content-Type: application/json" -d "$data" "http://localhost:8080/api/$endpoint"
}

dhis2_api_get() {
    local endpoint="$1"
    curl -s -u admin:district "http://localhost:8080/api/$endpoint"
}

# 1. Wait for DHIS2
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 30
    check_dhis2_health || echo "DHIS2 may not be ready yet."
fi

# 2. Get Metadata IDs (OrgUnit, Program, Attribute)
echo "Resolving Metadata IDs..."

# OrgUnit: Bo Government Hospital
OU_ID=$(dhis2_api_get "organisationUnits?filter=name:eq:Bo%20Government%20Hospital&fields=id" | jq -r '.organisationUnits[0].id')
echo "OrgUnit ID: $OU_ID"

# Program: MNCH / ANC (Antenatal Care)
PROG_ID=$(dhis2_api_get "programs?filter=name:ilike:MNCH%20/%20ANC&fields=id" | jq -r '.programs[0].id')
echo "Program ID: $PROG_ID"

# Tracked Entity Type: Person
TE_TYPE_ID=$(dhis2_api_get "trackedEntityTypes?filter=name:eq:Person&fields=id" | jq -r '.trackedEntityTypes[0].id')

# Attributes
# We need IDs for First Name, Last Name, and Mobile Number to create the patient correctly
ATTR_FNAME=$(dhis2_api_get "trackedEntityAttributes?filter=name:ilike:First%20name&fields=id" | jq -r '.trackedEntityAttributes[0].id')
ATTR_LNAME=$(dhis2_api_get "trackedEntityAttributes?filter=name:ilike:Last%20name&fields=id" | jq -r '.trackedEntityAttributes[0].id')
ATTR_PHONE=$(dhis2_api_get "trackedEntityAttributes?filter=name:ilike:Mobile%20phone&fields=id" | jq -r '.trackedEntityAttributes[0].id')

if [ -z "$ATTR_PHONE" ] || [ "$ATTR_PHONE" == "null" ]; then
    # Fallback search
    ATTR_PHONE=$(dhis2_api_get "trackedEntityAttributes?filter=name:ilike:Phone&fields=id" | jq -r '.trackedEntityAttributes[0].id')
fi

# 3. Check if Maria Kabbah exists, if so delete or reset her
echo "Checking for existing patient..."
EXISTING_TEI=$(dhis2_api_get "trackedEntityInstances?ou=$OU_ID&program=$PROG_ID&filter=$ATTR_FNAME:EQ:Maria&filter=$ATTR_LNAME:EQ:Kabbah" | jq -r '.trackedEntityInstances[0].trackedEntityInstance // empty')

if [ -n "$EXISTING_TEI" ]; then
    echo "Found existing patient ($EXISTING_TEI). Removing to ensure clean state..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/trackedEntityInstances/$EXISTING_TEI"
    sleep 2
fi

# 4. Create the Patient (Tracked Entity Instance)
echo "Creating new patient: Maria Kabbah..."
DATE_TODAY=$(date +%Y-%m-%d)

# JSON payload for TEI
read -r -d '' TEI_PAYLOAD <<EOF
{
  "trackedEntityType": "$TE_TYPE_ID",
  "orgUnit": "$OU_ID",
  "attributes": [
    { "attribute": "$ATTR_FNAME", "value": "Maria" },
    { "attribute": "$ATTR_LNAME", "value": "Kabbah" },
    { "attribute": "$ATTR_PHONE", "value": "000-000-000" }
  ],
  "enrollments": [
    {
      "orgUnit": "$OU_ID",
      "program": "$PROG_ID",
      "enrollmentDate": "$DATE_TODAY",
      "incidentDate": "$DATE_TODAY",
      "status": "ACTIVE"
    }
  ]
}
EOF

RESPONSE=$(dhis2_api_post "trackedEntityInstances" "$TEI_PAYLOAD")
TEI_ID=$(echo "$RESPONSE" | jq -r '.response.importSummaries[0].reference')

if [ -z "$TEI_ID" ] || [ "$TEI_ID" == "null" ]; then
    echo "ERROR: Failed to create patient. Response: $RESPONSE"
    # Fallback: Try to find her if creation claimed success but parsing failed
    TEI_ID=$(dhis2_api_get "trackedEntityInstances?ou=$OU_ID&program=$PROG_ID&filter=$ATTR_FNAME:EQ:Maria&filter=$ATTR_LNAME:EQ:Kabbah" | jq -r '.trackedEntityInstances[0].trackedEntityInstance')
fi

echo "Target TEI ID: $TEI_ID"
echo "$TEI_ID" > /tmp/target_tei_id.txt
echo "$OU_ID" > /tmp/target_ou_id.txt
echo "$PROG_ID" > /tmp/target_prog_id.txt
echo "$ATTR_PHONE" > /tmp/target_phone_attr_id.txt

# 5. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 60

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/task_start_time.txt
date -I > /tmp/task_date_iso.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient 'Maria Kabbah' created with ID: $TEI_ID"