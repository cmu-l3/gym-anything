#!/bin/bash
set -e
echo "=== Setting up Delete Erroneous Visit Task ==="
source /workspace/scripts/task_utils.sh

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Patient Exists (Bernhard Morar)
echo "Locating patient Bernhard Morar..."
PATIENT_UUID=$(get_patient_uuid "Bernhard Morar")

if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found, running seeder..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Bernhard Morar")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not find or create patient Bernhard Morar."
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"

# 3. Create the Erroneous Visit
# We create a visit starting NOW so it is clearly the "most recent" and "today"
echo "Creating erroneous visit..."

# Get Visit Type (Facility Visit)
VISIT_TYPE_UUID=$(omrs_db_query "SELECT uuid FROM visit_type WHERE name LIKE '%Facility%' LIMIT 1;")
if [ -z "$VISIT_TYPE_UUID" ]; then
    VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Fallback O3 default
fi

# Get Location (Outpatient Clinic)
LOCATION_UUID=$(omrs_db_query "SELECT uuid FROM location WHERE name LIKE '%Outpatient%' LIMIT 1;")
if [ -z "$LOCATION_UUID" ]; then
    LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Fallback O3 default
fi

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")

# Post via REST
VISIT_RESPONSE=$(omrs_post "/visit" "{
    \"patient\": \"$PATIENT_UUID\",
    \"visitType\": \"$VISIT_TYPE_UUID\",
    \"startDatetime\": \"$NOW_ISO\",
    \"location\": \"$LOCATION_UUID\"
}")

TARGET_VISIT_UUID=$(echo "$VISIT_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$TARGET_VISIT_UUID" ]; then
    echo "ERROR: Failed to create erroneous visit. Response: $VISIT_RESPONSE"
    exit 1
fi

echo "Created Erroneous Visit: $TARGET_VISIT_UUID"

# 4. Record State for Verification
# Save the target UUID to a file that export_result.sh can read
echo "$TARGET_VISIT_UUID" > /tmp/target_visit_uuid.txt
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt

# Count existing NON-voided visits for this patient (including the one we just made)
INITIAL_VISIT_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM visit WHERE patient_id=(SELECT patient_id FROM patient WHERE uuid='$PATIENT_UUID') AND voided=0;")
echo "$INITIAL_VISIT_COUNT" > /tmp/initial_visit_count.txt

# 5. Browser Setup
# Start at Home Page
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 6. Capture Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Patient: $PATIENT_UUID"
echo "Target Visit to Delete: $TARGET_VISIT_UUID"