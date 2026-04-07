#!/bin/bash
# Setup script for add_phone_number task
# Finds a patient, ensures they have NO phone number, and navigates to their chart.

set -e
echo "=== Setting up add_phone_number task ==="
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming (DB timestamp check)
date +%s > /tmp/task_start_time.txt

# 2. Identify a target patient
# We prefer a patient who has a name but might need a phone number.
# We will pick the first non-voided patient.
echo "Selecting target patient..."

# Get list of patients to find a suitable candidate
# We'll just take the first one found by the seed script, or search commonly seeded names
CANDIDATES=("John" "Jane" "Robert" "Meredith" "Arundhati" "Larissa")
PATIENT_UUID=""
PATIENT_ID=""
PATIENT_NAME=""

for name in "${CANDIDATES[@]}"; do
    # Try to find patient by name
    SEARCH_RESULT=$(omrs_db_query "SELECT p.patient_id, p2.uuid, pn.given_name, pn.family_name FROM patient p JOIN person p2 ON p.patient_id = p2.person_id JOIN person_name pn ON p2.person_id = pn.person_id WHERE pn.given_name LIKE '${name}%' AND p.voided=0 AND p2.dead=0 LIMIT 1")
    
    if [ -n "$SEARCH_RESULT" ]; then
        PATIENT_ID=$(echo "$SEARCH_RESULT" | awk '{print $1}')
        PATIENT_UUID=$(echo "$SEARCH_RESULT" | awk '{print $2}')
        PATIENT_NAME=$(echo "$SEARCH_RESULT" | awk '{print $3 " " $4}')
        break
    fi
done

# If no candidate found (rare if seeded), seed data now
if [ -z "$PATIENT_UUID" ]; then
    echo "No suitable patient found. Seeding data..."
    bash /workspace/scripts/seed_data.sh
    # Pick first available patient after seeding
    SEARCH_RESULT=$(omrs_db_query "SELECT p.patient_id, p2.uuid, pn.given_name, pn.family_name FROM patient p JOIN person p2 ON p.patient_id = p2.person_id JOIN person_name pn ON p2.person_id = pn.person_id WHERE p.voided=0 AND p2.dead=0 LIMIT 1")
    PATIENT_ID=$(echo "$SEARCH_RESULT" | awk '{print $1}')
    PATIENT_UUID=$(echo "$SEARCH_RESULT" | awk '{print $2}')
    PATIENT_NAME=$(echo "$SEARCH_RESULT" | awk '{print $3 " " $4}')
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not find or create a patient."
    exit 1
fi

echo "Target Patient: $PATIENT_NAME (ID: $PATIENT_ID, UUID: $PATIENT_UUID)"

# 3. Clean State: Remove any existing telephone number for this patient
echo "Ensuring no existing phone number..."
ATTR_TYPE_ID=$(omrs_db_query "SELECT person_attribute_type_id FROM person_attribute_type WHERE name = 'Telephone Number'")

if [ -n "$ATTR_TYPE_ID" ]; then
    omrs_db_query "UPDATE person_attribute SET voided=1, voided_by=1, date_voided=NOW(), void_reason='Task Setup' WHERE person_id=$PATIENT_ID AND person_attribute_type_id=$ATTR_TYPE_ID AND voided=0"
fi

# 4. Save context for export script
echo "$PATIENT_ID" > /tmp/task_patient_id.txt
echo "$PATIENT_UUID" > /tmp/task_patient_uuid.txt
echo "$PATIENT_NAME" > /tmp/task_patient_name.txt

# 5. Launch Application
# Navigate Firefox to the patient's chart
CHART_URL="http://localhost/openmrs/spa/patient/${PATIENT_UUID}/chart/Patient%20Summary"
echo "Navigating to: $CHART_URL"

ensure_openmrs_logged_in "$CHART_URL"

# 6. Verify Initial State
# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="