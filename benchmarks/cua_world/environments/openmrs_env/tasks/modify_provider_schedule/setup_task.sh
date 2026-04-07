#!/bin/bash
# Setup: modify_provider_schedule task
# Creates a provider 'Dr. Schedule Test' and a schedule block for Tomorrow (09:00-17:00).

echo "=== Setting up modify_provider_schedule task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Calculate dates (Tomorrow)
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
START_DT="${TOMORROW}T09:00:00.000+0000"
END_DT="${TOMORROW}T17:00:00.000+0000"
echo "Target Date: $TOMORROW"

# 2. Ensure Provider Exists: "Dr. Schedule Test"
# First check if person exists, else create
PERSON_UUID=$(omrs_get "/person?q=Schedule+Test&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null || echo "")

if [ -z "$PERSON_UUID" ]; then
    echo "Creating Person: Dr. Schedule Test"
    PERSON_PAYLOAD='{
        "names": [{"givenName": "Dr. Schedule", "familyName": "Test", "preferred": true}],
        "gender": "M",
        "birthdate": "1980-01-01"
    }'
    PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
    PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi

# Check if Provider exists for this person
PROVIDER_UUID=$(omrs_get "/provider?q=Schedule+Test&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r['results'] else '')" 2>/dev/null || echo "")

if [ -z "$PROVIDER_UUID" ]; then
    echo "Creating Provider role..."
    PROV_PAYLOAD="{\"person\": \"$PERSON_UUID\", \"identifier\": \"PROV-TEST-001\"}"
    PROVIDER_RESP=$(omrs_post "/provider" "$PROV_PAYLOAD")
    PROVIDER_UUID=$(echo "$PROVIDER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Provider UUID: $PROVIDER_UUID"

# 3. Get Location (Outpatient Clinic)
LOCATION_UUID=$(omrs_get "/location?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); locs=r.get('results',[]); print(next((l['uuid'] for l in locs if 'outpatient' in l.get('display','').lower()), locs[0]['uuid'] if locs else ''))" 2>/dev/null || echo "")
echo "Location UUID: $LOCATION_UUID"

# 4. Get an Appointment Service Type (needed for the block)
# Ensure at least one exists
SERVICE_UUID=$(omrs_get "/appointmentscheduling/appointmenttype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || echo "")

if [ -z "$SERVICE_UUID" ]; then
    echo "Creating 'General Consult' service type..."
    SVC_PAYLOAD='{"name": "General Consult", "duration": 15}'
    SVC_RESP=$(omrs_post "/appointmentscheduling/appointmenttype" "$SVC_PAYLOAD")
    SERVICE_UUID=$(echo "$SVC_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Service Type UUID: $SERVICE_UUID"

# 5. Create the Appointment Block (09:00 - 17:00)
# First, cleanup any existing blocks for this provider on this day to avoid overlaps/confusion
echo "Cleaning up existing blocks for tomorrow..."
# (Logic: fetch blocks for date range, delete if match provider)
# For simplicity in this setup, we assume the provider is clean or we just create a new one.
# But ideally we query. O3 Appointment Block API: /appointmentscheduling/appointmentblock?fromDate=...&toDate=...
# We will just attempt creation. If overlap, it might fail, but usually with a specific error.

BLOCK_PAYLOAD=$(cat <<EOF
{
  "startDate": "$START_DT",
  "endDate": "$END_DT",
  "provider": "$PROVIDER_UUID",
  "location": "$LOCATION_UUID",
  "types": ["$SERVICE_UUID"]
}
EOF
)

echo "Creating Schedule Block..."
BLOCK_RESP=$(omrs_post "/appointmentscheduling/appointmentblock" "$BLOCK_PAYLOAD")
BLOCK_UUID=$(echo "$BLOCK_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$BLOCK_UUID" ]; then
    echo "ERROR: Failed to create appointment block. Response:"
    echo "$BLOCK_RESP"
    # Fallback: Maybe block already exists? Try to find it.
    BLOCK_UUID=$(omrs_get "/appointmentscheduling/appointmentblock?fromDate=$TOMORROW&toDate=$TOMORROW&provider=$PROVIDER_UUID" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')")
fi

echo "Block UUID: $BLOCK_UUID"
echo "$BLOCK_UUID" > /tmp/target_block_uuid
echo "$TOMORROW" > /tmp/target_date

# 6. Launch Browser to Appointments Calendar
# URL structure for O3 Appointments usually: /openmrs/spa/appointments/calendar
APP_URL="http://localhost/openmrs/spa/appointments/calendar"
ensure_openmrs_logged_in "$APP_URL"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="
echo "Target Date: $TOMORROW"
echo "Provider: Dr. Schedule Test"
echo "Block UUID: $BLOCK_UUID"