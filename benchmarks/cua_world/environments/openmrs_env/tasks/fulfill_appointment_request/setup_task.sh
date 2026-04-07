#!/bin/bash
# Setup script for fulfill_appointment_request task
# 1. Creates/Ensures patient Isabella Martinez exists
# 2. Creates 'Dermatology Consultation' service
# 3. Creates a pending Appointment Request
# 4. Creates a Provider Schedule/Block so a slot exists to be booked
# 5. Launches Firefox

set -e
echo "=== Setting up fulfill_appointment_request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. GET/CREATE PATIENT
echo "Ensuring patient Isabella Martinez exists..."
PATIENT_UUID=$(get_patient_uuid "Isabella Martinez")

if [ -z "$PATIENT_UUID" ]; then
    echo "Creating patient Isabella Martinez..."
    # Generate OpenMRS ID
    IDGEN_SOURCE="8549f706-7e85-4c1d-9424-217d50a2988b" # From seed script
    GEN_ID=$(omrs_post "/idgen/identifiersource" "{\"generateIdentifiers\":true,\"sourceUuid\":\"$IDGEN_SOURCE\",\"numberToGenerate\":1}" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['identifiers'][0])" 2>/dev/null)
    
    # Create Person
    PERSON_PAYLOAD="{\"names\":[{\"givenName\":\"Isabella\",\"familyName\":\"Martinez\",\"preferred\":true}],\"gender\":\"F\",\"birthdate\":\"1995-05-20\",\"addresses\":[{\"address1\":\"123 Skin Lane\",\"cityVillage\":\"Boston\",\"country\":\"USA\"}]}"
    PERSON_UUID=$(omrs_post "/person" "$PERSON_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
    
    # Create Patient
    PATIENT_PAYLOAD="{\"person\":\"$PERSON_UUID\",\"identifiers\":[{\"identifier\":\"$GEN_ID\",\"identifierType\":\"05a29f94-c0ed-11e2-94be-8c13b969e334\",\"location\":\"44c3efb0-2583-4c80-a79e-1f756a03c0a1\",\"preferred\":true}]}"
    PATIENT_UUID=$(omrs_post "/patient" "$PATIENT_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
fi

echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt

# 2. CREATE SERVICE TYPE
echo "Ensuring Service Type 'Dermatology Consultation' exists..."
# Check existing
SERVICE_UUID=$(omrs_get "/appointmentscheduling/appointmenttype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(next((x['uuid'] for x in r.get('results',[]) if x['display'] == 'Dermatology Consultation'), ''))" 2>/dev/null || echo "")

if [ -z "$SERVICE_UUID" ]; then
    SERVICE_PAYLOAD="{\"name\":\"Dermatology Consultation\",\"description\":\"Skin check\",\"duration\":30}"
    SERVICE_UUID=$(omrs_post "/appointmentscheduling/appointmenttype" "$SERVICE_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Service UUID: $SERVICE_UUID"

# 3. CREATE APPOINTMENT REQUEST
echo "Creating Appointment Request..."
# Ensure no pending requests exist for this patient to avoid confusion
EXISTING_REQS=$(omrs_get "/appointmentscheduling/appointmentrequest?patient=$PATIENT_UUID&status=PENDING" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); [print(x['uuid']) for x in r.get('results',[])]" 2>/dev/null || true)

while IFS= read -r req_uuid; do
    if [ -n "$req_uuid" ]; then
        omrs_post "/appointmentscheduling/appointmentrequest/$req_uuid" "{\"status\":\"CANCELLED\"}" > /dev/null
    fi
done <<< "$EXISTING_REQS"

# Create new request
REQ_PAYLOAD="{\"patient\":\"$PATIENT_UUID\",\"appointmentType\":\"$SERVICE_UUID\",\"status\":\"PENDING\",\"minTimeFrameUnits\":\"DAYS\",\"minTimeFrameValue\":1,\"maxTimeFrameUnits\":\"WEEKS\",\"maxTimeFrameValue\":2,\"notes\":\"Rash on arm\"}"
REQ_UUID=$(omrs_post "/appointmentscheduling/appointmentrequest" "$REQ_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Request UUID: $REQ_UUID"
echo "$REQ_UUID" > /tmp/target_request_uuid.txt

# 4. CREATE PROVIDER SCHEDULE (AVAILABILITY)
# We need a slot for "Tomorrow 10:00 AM".
# We need a Provider and a Location.
PROVIDER_UUID=$(omrs_get "/provider?q=admin&v=default" | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['uuid'])")
LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Outpatient Clinic (standard O3 demo location)

# Calculate timestamps for tomorrow
TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
START_TIME="${TOMORROW}T09:00:00.000+0000"
END_TIME="${TOMORROW}T17:00:00.000+0000"

# Create Appointment Block
BLOCK_PAYLOAD="{\"startDate\":\"$START_TIME\",\"endDate\":\"$END_TIME\",\"provider\":\"$PROVIDER_UUID\",\"location\":\"$LOCATION_UUID\",\"types\":[\"$SERVICE_UUID\"]}"
BLOCK_UUID=$(omrs_post "/appointmentscheduling/appointmentblock" "$BLOCK_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
echo "Block UUID: $BLOCK_UUID"

# 5. WRITE INSTRUCTIONS FILE
echo "Writing details to file..."
TARGET_TIME_DISPLAY="$(date -d "tomorrow 10:00" +"%Y-%m-%d 10:00 AM")"
cat > /home/ga/appointment_details.txt << EOF
Target Appointment Details:
---------------------------
Patient: Isabella Martinez
Service: Dermatology Consultation
Date: $TOMORROW
Time: 10:00 AM - 10:30 AM
EOF
chown ga:ga /home/ga/appointment_details.txt

# 6. LAUNCH FIREFOX
# Navigate to the Appointments home (usually /openmrs/spa/appointments/home or similar)
# We'll stick to the home page or specific app link if known. 
# In O3, the app is usually at /openmrs/spa/appointments
APP_URL="http://localhost/openmrs/spa/appointments/appointments-requests"

ensure_openmrs_logged_in "$APP_URL"

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="