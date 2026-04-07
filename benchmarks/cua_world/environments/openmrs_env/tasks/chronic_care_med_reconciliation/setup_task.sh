#!/bin/bash
# Setup: chronic_care_med_reconciliation task
# Creates patient "Elena Vasques" (misspelled) with wrong address,
# pre-existing Penicillin allergy, chronic conditions, and 3 active
# drug orders (Metformin, Codeine, Lisinopril). Agent must correct
# demographics, add Morphine allergy, discontinue opioid, prescribe
# replacement, record vitals, order labs, and schedule follow-up.

set -e
echo "=== Setting up chronic_care_med_reconciliation task ==="
source /workspace/scripts/task_utils.sh

# ── Helper: find a concept UUID by name search ──────────────────────────────
find_concept_uuid() {
    local search_term="$1"
    local encoded
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$search_term'))")
    omrs_get "/concept?q=${encoded}&v=default&limit=10" | \
        python3 -c "
import sys, json
search = '${search_term}'.lower()
r = json.load(sys.stdin)
results = r.get('results', [])
# Prefer exact match
for c in results:
    if c.get('display', '').lower() == search:
        print(c['uuid']); exit()
# Fall back to first result
if results:
    print(results[0]['uuid'])
" 2>/dev/null || echo ""
}

# ── Helper: get admin provider UUID ──────────────────────────────────────────
get_admin_provider() {
    omrs_get "/provider?q=admin&v=default" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null || echo ""
}

# ── 1. Delete stale output files BEFORE recording timestamp ──────────────────
rm -f /tmp/chronic_care_med_reconciliation_result.json
rm -f /tmp/chronic_care_med_reconciliation_patient_uuid
rm -f /tmp/chronic_care_med_reconciliation_start_ts
rm -f /tmp/chronic_care_med_reconciliation_initial_*.txt
rm -f /tmp/chronic_care_med_reconciliation_*_screenshot.png

# ── 2. Record start timestamp (anti-gaming) ──────────────────────────────────
date +%s > /tmp/chronic_care_med_reconciliation_start_ts

# ── 3. Clean up any existing test patients ───────────────────────────────────
echo "Cleaning up previous test data..."
for search_name in "Elena Vasquez" "Elena Vasques"; do
    EXISTING_UUIDS=$(omrs_get "/patient?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$search_name'))")&v=default" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); [print(p['uuid']) for p in r.get('results',[])]" 2>/dev/null || true)
    while IFS= read -r uuid; do
        if [ -n "$uuid" ]; then
            omrs_delete "/patient/$uuid" > /dev/null 2>&1 || true
            echo "  Deleted existing patient ($uuid)"
        fi
    done <<< "$EXISTING_UUIDS"
done

# ── 4. Create patient "Elena Vasques" (misspelled) with wrong address ────────
echo "Creating patient Elena Vasques (misspelled)..."

PERSON_PAYLOAD='{
    "names": [{"givenName": "Elena", "familyName": "Vasques", "preferred": true}],
    "gender": "F",
    "birthdate": "1962-08-14",
    "addresses": [{
        "address1": "123 Old Street",
        "cityVillage": "Anytown",
        "stateProvince": "Oregon",
        "country": "United States",
        "postalCode": "00000",
        "preferred": true
    }]
}'
PERSON_RESP=$(omrs_post "/person" "$PERSON_PAYLOAD")
PERSON_UUID=$(echo "$PERSON_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$PERSON_UUID" ]; then
    echo "ERROR: Failed to create person. Response: $PERSON_RESP"
    exit 1
fi

# Generate OpenMRS ID
ID_GEN_PAYLOAD='{"generateIdentifiers": true, "sourceUuid": "8549f706-7e85-4c1d-9424-217d50a2988b", "numberToGenerate": 1}'
ID_RESP=$(omrs_post "/idgen/identifiersource" "$ID_GEN_PAYLOAD")
OPENMRS_ID=$(echo "$ID_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('identifiers',[None])[0])")

if [ -z "$OPENMRS_ID" ] || [ "$OPENMRS_ID" == "None" ]; then
    echo "ERROR: Failed to generate OpenMRS ID."
    exit 1
fi

PATIENT_PAYLOAD="{
    \"person\": \"$PERSON_UUID\",
    \"identifiers\": [{
        \"identifier\": \"$OPENMRS_ID\",
        \"identifierType\": \"05a29f94-c0ed-11e2-94be-8c13b969e334\",
        \"location\": \"44c3efb0-2583-4c80-a79e-1f756a03c0a1\",
        \"preferred\": true
    }]
}"
PATIENT_RESP=$(omrs_post "/patient" "$PATIENT_PAYLOAD")
PATIENT_UUID=$(echo "$PATIENT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Failed to create patient."
    exit 1
fi
echo "Created patient: Elena Vasques ($PATIENT_UUID)"
echo "$PATIENT_UUID" > /tmp/chronic_care_med_reconciliation_patient_uuid

# ── 5. Add pre-existing Penicillin allergy ───────────────────────────────────
echo "Adding pre-existing Penicillin allergy..."
PENICILLIN_UUID=$(find_concept_uuid "Penicillin")
# Severity: MILD (CIEL 1498)
MILD_SEV_UUID=$(find_concept_uuid "Mild")
# Reaction: Rash
RASH_UUID=$(find_concept_uuid "Rash")

if [ -n "$PENICILLIN_UUID" ]; then
    ALLERGY_PAYLOAD="{
        \"allergen\": {
            \"allergenType\": \"DRUG\",
            \"codedAllergen\": {\"uuid\": \"$PENICILLIN_UUID\"}
        }"

    # Add severity if found
    if [ -n "$MILD_SEV_UUID" ]; then
        ALLERGY_PAYLOAD="$ALLERGY_PAYLOAD, \"severity\": {\"uuid\": \"$MILD_SEV_UUID\"}"
    fi

    # Add reaction if found
    if [ -n "$RASH_UUID" ]; then
        ALLERGY_PAYLOAD="$ALLERGY_PAYLOAD, \"reactions\": [{\"reaction\": {\"uuid\": \"$RASH_UUID\"}}]"
    fi

    ALLERGY_PAYLOAD="{${ALLERGY_PAYLOAD#\{} }"

    ALLERGY_RESP=$(omrs_post "/patient/$PATIENT_UUID/allergy" "$ALLERGY_PAYLOAD" 2>/dev/null || echo "")
    if echo "$ALLERGY_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin); assert r.get('uuid')" 2>/dev/null; then
        echo "  Penicillin allergy added (coded)"
    else
        echo "  WARNING: Coded allergy creation may have failed. Trying non-coded..."
        NC_PAYLOAD="{\"allergen\":{\"allergenType\":\"DRUG\",\"nonCodedAllergen\":\"Penicillin\"}}"
        omrs_post "/patient/$PATIENT_UUID/allergy" "$NC_PAYLOAD" > /dev/null 2>&1 || echo "  WARNING: Could not add Penicillin allergy"
    fi
else
    echo "  Penicillin concept not found. Using non-coded allergen..."
    NC_PAYLOAD="{\"allergen\":{\"allergenType\":\"DRUG\",\"nonCodedAllergen\":\"Penicillin\"}}"
    omrs_post "/patient/$PATIENT_UUID/allergy" "$NC_PAYLOAD" > /dev/null 2>&1 || echo "  WARNING: Could not add Penicillin allergy"
fi

# ── 6. Add pre-existing conditions ──────────────────────────────────────────
echo "Adding pre-existing conditions..."
# Use verified CIEL concept UUIDs (confirmed to exist in this installation)
# Essential hypertension: CIEL 140987
HYPERTENSION_UUID="140987AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
# Diabetes mellitus: CIEL 119481
DIABETES_UUID="119481AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

for COND_UUID in "$HYPERTENSION_UUID" "$DIABETES_UUID"; do
    COND_PAYLOAD="{
        \"condition\": {\"coded\": \"$COND_UUID\"},
        \"patient\": \"$PATIENT_UUID\",
        \"clinicalStatus\": \"ACTIVE\",
        \"verificationStatus\": \"CONFIRMED\"
    }"
    COND_RESP=$(omrs_post "/condition" "$COND_PAYLOAD" 2>/dev/null || echo "")
    COND_NAME=$(echo "$COND_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('condition',{}).get('display','unknown'))" 2>/dev/null || echo "unknown")
    echo "  Added condition: $COND_NAME"
done

# ── 7. Create a past visit with encounter for pre-existing drug orders ───────
echo "Creating past visit for pre-existing medication orders..."

VISIT_TYPE_UUID="7b0f5697-27e3-40c4-8bae-f4049abfb4ed"  # Facility Visit
LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1"     # Outpatient Clinic
CARE_SETTING="6f0c9a92-6f24-11e3-af88-005056821db0"      # Outpatient
ROUTE_ORAL="160240AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"          # Oral route
DOSE_UNIT_MG="161553AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"        # mg
FREQ_DAILY="160862AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"          # Once daily
# Dynamically find Consultation encounter type
ENC_TYPE_CONSULT=$(omrs_get "/encountertype?v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(next((e['uuid'] for e in r.get('results',[]) if 'consultation' in e.get('display','').lower()), r['results'][0]['uuid'] if r.get('results') else ''))" 2>/dev/null || echo "")

# Past visit: 7 days ago — create OPEN first, then close after adding orders
PAST_START=$(date -u -d "-7 days" +"%Y-%m-%dT09:00:00.000+0000" 2>/dev/null || date -u -v-7d +"%Y-%m-%dT09:00:00.000+0000" 2>/dev/null)

VISIT_PAYLOAD="{
    \"patient\": \"$PATIENT_UUID\",
    \"visitType\": \"$VISIT_TYPE_UUID\",
    \"startDatetime\": \"$PAST_START\",
    \"location\": \"$LOCATION_UUID\"
}"
PAST_VISIT_UUID=$(omrs_post "/visit" "$VISIT_PAYLOAD" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null || echo "")
echo "  Past visit: $PAST_VISIT_UUID"

# Create encounter within the (still open) past visit
PAST_ENC_DATE=$(date -u -d "-7 days" +"%Y-%m-%dT09:15:00.000+0000" 2>/dev/null || date -u -v-7d +"%Y-%m-%dT09:15:00.000+0000" 2>/dev/null)
ENC_PAYLOAD="{
    \"patient\": \"$PATIENT_UUID\",
    \"visit\": \"$PAST_VISIT_UUID\",
    \"encounterType\": \"$ENC_TYPE_CONSULT\",
    \"encounterDatetime\": \"$PAST_ENC_DATE\"
}"
ENC_UUID=$(omrs_post "/encounter" "$ENC_PAYLOAD" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null || echo "")
echo "  Past encounter: $ENC_UUID"

if [ -z "$ENC_UUID" ]; then
    echo "  ERROR: Failed to create encounter — drug orders will fail"
fi

# Get admin provider UUID for orderer
ADMIN_PROVIDER=$(get_admin_provider)
[ -z "$ADMIN_PROVIDER" ] && ADMIN_PROVIDER="c2299800-cca9-11e0-9572-0800200c9a66"

# ── 8. Create 3 pre-existing drug orders ─────────────────────────────────────
echo "Creating pre-existing medication orders..."

# Find drug concepts dynamically
METFORMIN_CONCEPT=$(find_concept_uuid "Metformin")
CODEINE_CONCEPT=$(find_concept_uuid "Codeine")
LISINOPRIL_CONCEPT=$(find_concept_uuid "Lisinopril")

create_drug_order() {
    local drug_name="$1"
    local concept_uuid="$2"
    local dose="$3"

    if [ -z "$concept_uuid" ]; then
        echo "  WARNING: $drug_name concept not found — skipping order"
        return 1
    fi

    local ORDER_PAYLOAD="{
        \"type\": \"drugorder\",
        \"patient\": \"$PATIENT_UUID\",
        \"concept\": \"$concept_uuid\",
        \"encounter\": \"$ENC_UUID\",
        \"careSetting\": \"$CARE_SETTING\",
        \"orderer\": \"$ADMIN_PROVIDER\",
        \"dosingType\": \"org.openmrs.SimpleDosingInstructions\",
        \"dose\": $dose,
        \"doseUnits\": \"$DOSE_UNIT_MG\",
        \"route\": \"$ROUTE_ORAL\",
        \"frequency\": \"$FREQ_DAILY\",
        \"quantity\": 30,
        \"quantityUnits\": \"1513AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",
        \"numRefills\": 3,
        \"action\": \"NEW\"
    }"
    local ORDER_UUID
    ORDER_UUID=$(omrs_post "/order" "$ORDER_PAYLOAD" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('uuid',''))" 2>/dev/null || echo "")

    if [ -n "$ORDER_UUID" ]; then
        echo "  Created $drug_name order: $ORDER_UUID"
        return 0
    else
        echo "  WARNING: Failed to create $drug_name order"
        return 1
    fi
}

create_drug_order "Metformin" "$METFORMIN_CONCEPT" 500
CODEINE_ORDER_CREATED=false
if create_drug_order "Codeine" "$CODEINE_CONCEPT" 30; then
    CODEINE_ORDER_CREATED=true
fi
create_drug_order "Lisinopril" "$LISINOPRIL_CONCEPT" 10

if [ "$CODEINE_ORDER_CREATED" != "true" ]; then
    echo "WARNING: Codeine order not created — the medication reconciliation step may not work."
    echo "  Agent will still be asked to review medications."
fi

# ── 8b. Close the past visit now that orders are created ─────────────────────
echo "Closing past visit..."
if [ -n "$PAST_VISIT_UUID" ]; then
    PAST_END=$(date -u -d "-7 days" +"%Y-%m-%dT10:30:00.000+0000" 2>/dev/null || date -u -v-7d +"%Y-%m-%dT10:30:00.000+0000" 2>/dev/null)
    omrs_post "/visit/$PAST_VISIT_UUID" "{\"stopDatetime\":\"$PAST_END\"}" > /dev/null 2>&1 || true
    echo "  Past visit closed"
fi

# ── 8c. Ensure at least one appointment service exists ───────────────────────
echo "Ensuring appointment service exists..."
APPT_SVC_COUNT=$(omrs_get "/appointmentService/all/default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r) if isinstance(r,list) else 0)" 2>/dev/null || echo "0")
if [ "$APPT_SVC_COUNT" = "0" ]; then
    echo "  Creating 'General Medicine' appointment service..."
    omrs_post "/appointmentService" '{"name":"General Medicine","description":"General medicine consultation","durationMins":30,"color":"#006400"}' > /dev/null 2>&1 || true
    echo "  Appointment service created"
else
    echo "  Appointment service already exists ($APPT_SVC_COUNT found)"
fi

# ── 9. Record initial state for verification ─────────────────────────────────
echo "Recording initial state..."

INITIAL_ALLERGY_COUNT=$(omrs_get "/patient/$PATIENT_UUID/allergy" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); data=r.get('results',r) if isinstance(r,dict) else r; print(len(data) if isinstance(data,list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_ALLERGY_COUNT" > /tmp/chronic_care_med_reconciliation_initial_allergy_count.txt

INITIAL_COND_COUNT=$(omrs_get "/condition?patientUuid=$PATIENT_UUID&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_COND_COUNT" > /tmp/chronic_care_med_reconciliation_initial_condition_count.txt

INITIAL_ORDER_COUNT=$(omrs_get "/order?patient=$PATIENT_UUID&v=default&limit=100" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print(len(r.get('results',[])))" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/chronic_care_med_reconciliation_initial_order_count.txt

INITIAL_APPT_COUNT=$(omrs_get "/appointment?patientUuid=$PATIENT_UUID" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); data=r.get('results',r) if isinstance(r,dict) else r; print(len(data) if isinstance(data,list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_APPT_COUNT" > /tmp/chronic_care_med_reconciliation_initial_appt_count.txt

# ── 10. Open browser to patient chart ────────────────────────────────────────
echo "Navigating to patient chart..."
PATIENT_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$PATIENT_URL"
sleep 2

# ── 11. Take initial screenshot ──────────────────────────────────────────────
take_screenshot /tmp/chronic_care_med_reconciliation_start_screenshot.png

echo ""
echo "=== chronic_care_med_reconciliation setup complete ==="
echo ""
echo "Patient: Elena Vasques (misspelled — agent must correct to Vasquez)"
echo "  DOB: 1962-08-14 | Gender: Female"
echo "  Address: 123 Old Street, Anytown, Oregon, 00000 (wrong — agent must update)"
echo "  Existing allergy: Penicillin"
echo "  Existing conditions: Type 2 DM, Essential HTN"
echo "  Active medications: Metformin 500mg, Codeine 30mg, Lisinopril 10mg"
echo ""
echo "TASK:"
echo "  1. Correct name to Vasquez, update address to Portland"
echo "  2. Start Facility Visit"
echo "  3. Record vitals: BP 158/94, Wt 87.3, Ht 165, Temp 36.8, Pulse 82, SpO2 96"
echo "  4. Add allergy: Morphine (Anaphylaxis, Severe)"
echo "  5. Discontinue opioid medication (Codeine)"
echo "  6. Prescribe Acetaminophen 500mg oral twice daily"
echo "  7. Order labs: HbA1c, Serum Creatinine"
echo "  8. Schedule follow-up within 14 days"
echo ""
echo "Login: admin / Admin123"
