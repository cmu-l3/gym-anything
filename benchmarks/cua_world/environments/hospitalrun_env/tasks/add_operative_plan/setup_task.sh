#!/bin/bash
echo "=== Setting up add_operative_plan task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 2. Verify Patient Exists (Ahmed Hassan Ali - P00002)
# Re-seed if missing to ensure consistent starting state
echo "Verifying patient Ahmed Hassan Ali..."
PATIENT_ID="patient_p1_000002"
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" 2>/dev/null | grep -o "Ahmed Hassan Ali" || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Ahmed Hassan Ali..."
    # Create patient doc
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00002",
            "displayName": "Ali, Ahmed Hassan",
            "firstName": "Ahmed Hassan",
            "lastName": "Ali",
            "sex": "Male",
            "dateOfBirth": "11/22/1978",
            "bloodType": "A+",
            "status": "Active",
            "address": "123 Nile St, Cairo, Egypt",
            "phone": "20-123-456-7890",
            "email": "ahmed.ali@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# 3. Clean up existing operative plans for this patient
# We want to ensure the agent creates a NEW one, and we don't detect an old run.
echo "Cleaning up previous operative plans for this patient..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        d = doc.get('data', doc)
        # Check if it looks like an operative plan for our patient
        # Note: HospitalRun types can vary, but usually 'operativePlan'
        doc_type = d.get('type', doc.get('type', ''))
        patient_ref = d.get('patient', doc.get('patient', ''))
        
        # Heuristic: delete if it matches our patient AND contains 'Cholecystectomy'
        if '${PATIENT_ID}' in patient_ref and 'Cholecystectomy' in json.dumps(doc):
            print(row['id'] + ' ' + doc.get('_rev', ''))
except:
    pass
" | while read -r doc_id rev; do
    if [ -n "$doc_id" ]; then
        echo "Deleting stale plan: $doc_id"
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null || true
    fi
done

# 4. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Prepare Browser
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to patients list as neutral starting point
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 6. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="