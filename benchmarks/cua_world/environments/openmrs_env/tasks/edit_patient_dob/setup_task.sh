#!/bin/bash
# Setup: edit_patient_dob task
# Ensures patient 'Mario Vega' exists with a WRONG date of birth (not 1980-03-15).

echo "=== Setting up edit_patient_dob task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

TARGET_GIVEN="Mario"
TARGET_FAMILY="Vega"
TARGET_DOB="1980-03-15"
WRONG_DOB="1990-03-15"

# 1. Find or Create 'Mario Vega'
echo "Ensuring patient $TARGET_GIVEN $TARGET_FAMILY exists..."

# Search by name
PATIENT_UUID=$(get_patient_uuid "$TARGET_GIVEN $TARGET_FAMILY")

if [ -z "$PATIENT_UUID" ]; then
    echo "  Mario Vega not found. repurposing an existing patient..."
    
    # Get any existing patient (Synthea seeds 10)
    ANY_PATIENT=$(omrs_get "/patient?v=default&limit=1" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)
    
    if [ -z "$ANY_PATIENT" ]; then
        echo "  No patients found! Running seed script..."
        bash /workspace/scripts/seed_data.sh
        sleep 5
        ANY_PATIENT=$(omrs_get "/patient?v=default&limit=1" | \
            python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)
    fi
    
    if [ -z "$ANY_PATIENT" ]; then
        echo "ERROR: Could not find or seed any patients."
        exit 1
    fi
    
    PATIENT_UUID="$ANY_PATIENT"
    PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
    
    # Update name to Mario Vega
    echo "  Renaming patient $PATIENT_UUID to $TARGET_GIVEN $TARGET_FAMILY..."
    
    # Get preferred name UUID
    NAME_UUID=$(omrs_get "/person/$PERSON_UUID/name" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || true)
    
    if [ -n "$NAME_UUID" ]; then
        # Update existing name
        omrs_post "/person/$PERSON_UUID/name/$NAME_UUID" "{\"givenName\":\"$TARGET_GIVEN\",\"familyName\":\"$TARGET_FAMILY\"}" > /dev/null
    else
        # Create new name
        omrs_post "/person/$PERSON_UUID/name" "{\"givenName\":\"$TARGET_GIVEN\",\"familyName\":\"$TARGET_FAMILY\",\"preferred\":true}" > /dev/null
    fi
    
    # Force re-index/search delay
    sleep 2
fi

echo "Target Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt

# 2. Ensure DOB is WRONG (not 1980-03-15)
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
CURRENT_DOB=$(omrs_get "/person/$PERSON_UUID" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('birthdate','').split('T')[0])" 2>/dev/null || true)

echo "Current DOB: $CURRENT_DOB"

if [ "$CURRENT_DOB" == "$TARGET_DOB" ]; then
    echo "  DOB is already $TARGET_DOB. Resetting to $WRONG_DOB..."
    omrs_post "/person/$PERSON_UUID" "{\"birthdate\":\"$WRONG_DOB\"}" > /dev/null
    echo "  DOB reset complete."
else
    echo "  DOB is already incorrect (Good)."
fi

# 3. Save initial state for verification
echo "$CURRENT_DOB" > /tmp/initial_dob.txt

# 4. Open Firefox to Home Page (Agent must search)
ensure_openmrs_logged_in "http://localhost/openmrs/spa/home"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Target: $TARGET_GIVEN $TARGET_FAMILY"
echo "Goal DOB: $TARGET_DOB"