#!/bin/bash
# Setup: discontinue_medication task
# Ensures patient exists, has an active visit, and has an ACTIVE Aspirin order to discontinue.

set -e
echo "=== Setting up discontinue_medication task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Find or Create Patient "Khadijah Kirlin"
PATIENT_NAME="Khadijah Kirlin"
echo "Locating patient: $PATIENT_NAME..."
PATIENT_UUID=$(get_patient_uuid "$PATIENT_NAME")

if [ -z "$PATIENT_UUID" ]; then
    echo "Patient not found. Running seed script..."
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "$PATIENT_NAME")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Failed to find or create patient $PATIENT_NAME"
    exit 1
fi

echo "Patient UUID: $PATIENT_UUID"

# 3. Create an active visit if one doesn't exist
# Check for active visit
ACTIVE_VISIT=$(omrs_get "/visit?patient=$PATIENT_UUID&includeInactive=false&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); res=r.get('results',[]); print(res[0]['uuid'] if res else '')" 2>/dev/null || echo "")

if [ -z "$ACTIVE_VISIT" ]; then
    echo "Creating new active visit..."
    # Get required UUIDs
    VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed" # Facility Visit
    LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1"   # Outpatient Clinic
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    
    VISIT_PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "visitType": "$VISIT_TYPE_UUID",
  "startDatetime": "$NOW",
  "location": "$LOCATION_UUID"
}
EOF
)
    ACTIVE_VISIT=$(omrs_post "/visit" "$VISIT_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Active Visit UUID: $ACTIVE_VISIT"

# 4. Create the 'Aspirin' Drug Order (if not already active)
# Common UUIDs for O3 Ref App / CIEL
ASPIRIN_CONCEPT="1539AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
CARE_SETTING="6f0c9a92-6f24-11e3-af88-005056821db0" # Outpatient
ROUTE_ORAL="160240AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
DOSE_UNIT_MG="161553AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
FREQ_DAILY="160862AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
ORDER_TYPE_DRUG="131168f4-15f5-102d-96e4-000c29c2a5d7"

# Check if already active
EXISTING_ORDER=$(omrs_get "/order?patient=$PATIENT_UUID&careSetting=$CARE_SETTING&status=active&v=full" | \
    python3 -c "
import sys,json
r=json.load(sys.stdin)
for o in r.get('results',[]):
    if o.get('concept',{}).get('uuid') == '$ASPIRIN_CONCEPT':
        print(o['uuid'])
        break
" 2>/dev/null || echo "")

if [ -n "$EXISTING_ORDER" ]; then
    echo "Active Aspirin order already exists: $EXISTING_ORDER"
    TARGET_ORDER_UUID="$EXISTING_ORDER"
else
    echo "Creating new Aspirin order..."
    
    # We need an encounter for the order
    ENC_TYPE="fb1d5918-a687-438a-b851-9dc556e4085f" # Consultation (standard)
    ENC_PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "visit": "$ACTIVE_VISIT",
  "encounterType": "$ENC_TYPE",
  "encounterDatetime": "$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")"
}
EOF
)
    ENC_UUID=$(omrs_post "/encounter" "$ENC_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
    
    # Create Order
    ORDER_PAYLOAD=$(cat <<EOF
{
  "type": "drugorder",
  "patient": "$PATIENT_UUID",
  "concept": "$ASPIRIN_CONCEPT",
  "encounter": "$ENC_UUID",
  "careSetting": "$CARE_SETTING",
  "orderer": "$(get_admin_provider_uuid 2>/dev/null || echo 'c2299800-cca9-11e0-9572-0800200c9a66')",
  "dosingType": "org.openmrs.SimpleDosingInstructions",
  "dose": 81,
  "doseUnits": "$DOSE_UNIT_MG",
  "route": "$ROUTE_ORAL",
  "frequency": "$FREQ_DAILY",
  "action": "NEW"
}
EOF
)
    TARGET_ORDER_UUID=$(omrs_post "/order" "$ORDER_PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")
fi

if [ -z "$TARGET_ORDER_UUID" ]; then
    echo "ERROR: Could not create Aspirin order."
    exit 1
fi

echo "Target Order UUID: $TARGET_ORDER_UUID"

# 5. Save Context for Verification
cat > /tmp/task_context.json <<EOF
{
  "patient_uuid": "$PATIENT_UUID",
  "target_order_uuid": "$TARGET_ORDER_UUID",
  "drug_concept": "$ASPIRIN_CONCEPT"
}
EOF

# 6. Launch Firefox and Navigate to Patient Chart
echo "Navigating to patient chart..."
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Orders"
ensure_openmrs_logged_in "$PATIENT_URL"

# 7. Initial Screenshot
echo "Capturing initial state..."
sleep 2 # wait for UI render
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="