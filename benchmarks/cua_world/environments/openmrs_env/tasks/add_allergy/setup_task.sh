#!/bin/bash
# Setup: add_allergy task
# Removes existing Bee venom allergy for Clarinda Rolfson (if any), then opens her chart.

echo "=== Setting up add_allergy task ==="
source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Find Clarinda Rolfson
echo "Locating Clarinda Rolfson..."
PATIENT_UUID=$(get_patient_uuid "Clarinda Rolfson")
if [ -z "$PATIENT_UUID" ]; then
    bash /workspace/scripts/seed_data.sh || true
    sleep 5
    PATIENT_UUID=$(get_patient_uuid "Clarinda Rolfson")
fi
echo "Patient UUID: $PATIENT_UUID"
echo "$PATIENT_UUID" > /tmp/task_patient_uuid
PERSON_UUID=$(get_person_uuid "$PATIENT_UUID")
echo "Person UUID: $PERSON_UUID"

# Remove any pre-existing Bee venom allergy
echo "Removing any existing Bee venom allergy..."
EXISTING_ALLERGIES=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "
import sys,json
r=json.load(sys.stdin)
for a in r.get('results',[]):
    allergen = a.get('allergen',{})
    name = (allergen.get('codedAllergen',{}) or {}).get('display','') or allergen.get('nonCodedAllergen','')
    if 'bee' in name.lower() or 'venom' in name.lower():
        print(a['uuid'])
" 2>/dev/null || true)
while IFS= read -r a_uuid; do
    [ -n "$a_uuid" ] && omrs_delete "/allergy/$a_uuid" > /dev/null || true
done <<< "$EXISTING_ALLERGIES"

# Record initial allergy count
INITIAL_COUNT=$(omrs_get "/allergy?patient=$PATIENT_UUID&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_allergy_count

# Open Firefox on patient Allergies chart panel
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Allergies"
ensure_openmrs_logged_in "$PATIENT_URL"
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== add_allergy task setup complete ==="
echo ""
echo "TASK: Add allergy for Clarinda Rolfson"
echo "  Allergen:  Bee venom"
echo "  Reaction:  Hives"
echo "  Severity:  Mild"
echo ""
echo "Login: admin / Admin123"
