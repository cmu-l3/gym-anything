#!/bin/bash
# Setup script for record_visit_note task
# Selects a patient, ensures they have an active visit, and navigates to their chart.

set -e
echo "=== Setting up record_visit_note task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Select a patient (Use a stable Synthea patient if available, or search)
# We prioritize patients who already exist from the seed script
echo "Selecting patient..."
# Try to find a patient from the seed list (often "John", "Jane", "Test")
# fallback to querying for any patient
PATIENT_UUID=""
PATIENT_NAME=""

# Try specific seeded names first
for name in "John" "Jane" "Robert" "Maria"; do
    RESULTS=$(omrs_get "/patient?q=${name}&v=default")
    PATIENT_UUID=$(echo "$RESULTS" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')")
    if [ -n "$PATIENT_UUID" ]; then
        PATIENT_NAME=$(echo "$RESULTS" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['person']['display'])")
        break
    fi
done

# If still no patient, run seed script and try again
if [ -z "$PATIENT_UUID" ]; then
    echo "No suitable patient found. Running seed data script..."
    bash /workspace/scripts/seed_data.sh
    # Try finding "John" again after seeding
    RESULTS=$(omrs_get "/patient?q=John&v=default")
    PATIENT_UUID=$(echo "$RESULTS" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')")
    PATIENT_NAME="John"
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not find or create a patient."
    exit 1
fi

echo "Selected Patient: $PATIENT_NAME ($PATIENT_UUID)"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid.txt
echo "$PATIENT_NAME" > /tmp/task_patient_name.txt

# 2. Ensure Active Visit exists
# Check for active visits
OPEN_VISITS=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default")
VISIT_UUID=$(echo "$OPEN_VISITS" | python3 -c "import sys,json; r=json.load(sys.stdin); res=r.get('results',[]); print(res[0]['uuid'] if res else '')")

if [ -z "$VISIT_UUID" ]; then
    echo "No active visit found. Creating one..."
    
    # Get necessary UUIDs for creation
    VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Facility Visit
    LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1"   # Outpatient Clinic
    
    # Create visit
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "visitType": "$VISIT_TYPE_UUID",
  "location": "$LOCATION_UUID",
  "startDatetime": "$NOW"
}
EOF
)
    VISIT_RESP=$(omrs_post "/visit" "$PAYLOAD")
    VISIT_UUID=$(echo "$VISIT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    
    if [ -z "$VISIT_UUID" ]; then
        echo "ERROR: Failed to create visit."
        exit 1
    fi
    echo "Created active visit: $VISIT_UUID"
else
    echo "Found existing active visit: $VISIT_UUID"
fi

echo "$VISIT_UUID" > /tmp/task_visit_uuid.txt

# 3. Record initial encounter count (for simple heuristic checks)
ENC_COUNT=$(omrs_get "/encounter?patient=$PATIENT_UUID&v=count&limit=1" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('totalCount', 0))")
echo "$ENC_COUNT" > /tmp/initial_encounter_count.txt

# 4. Launch Browser at Patient Chart
CHART_URL="http://localhost/openmrs/spa/patient/${PATIENT_UUID}/chart/Patient%20Summary"
echo "Navigating to: $CHART_URL"

ensure_openmrs_logged_in "$CHART_URL"

# 5. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="