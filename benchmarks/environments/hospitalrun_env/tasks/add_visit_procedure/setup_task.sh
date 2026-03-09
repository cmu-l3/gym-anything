#!/bin/bash
echo "=== Setting up add_visit_procedure task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Verify HospitalRun is running
echo "Checking HospitalRun availability..."
wait_for_hospitalrun 60

# 2. Clean up any existing procedures for this patient to ensure clean state
# We look for procedures linked to Mei Lin Chen or her visit and delete them.
echo "Cleaning up previous procedures..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check if it's a procedure and linked to our patient/visit
    is_procedure = (doc.get('type') == 'procedure' or d.get('procedureDescription'))
    patient_ref = d.get('patient', '')
    visit_ref = d.get('visit', '')
    
    if is_procedure and ('patient_p1_000003' in patient_ref or 'visit_p1_000003' in visit_ref):
        print(row['id'] + '|' + doc.get('_rev',''))
" | while IFS='|' read -r doc_id rev; do
    if [ -n "$doc_id" ]; then
        echo "Deleting stale procedure: $doc_id"
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
    fi
done

# 3. Ensure Patient "Mei Lin Chen" exists
echo "Ensuring patient Mei Lin Chen exists..."
PATIENT_DOC=$(cat <<EOF
{
  "data": {
    "friendlyId": "P00003",
    "displayName": "Chen, Mei Lin",
    "firstName": "Mei Lin",
    "lastName": "Chen",
    "sex": "Female",
    "dateOfBirth": "09/22/1988",
    "bloodType": "A+",
    "status": "Active",
    "address": "123 Cherry Blossom Ln, San Francisco, CA 94110",
    "phone": "415-555-0199",
    "email": "meilin.chen@example.com",
    "patientType": "Inpatient"
  }
}
EOF
)
# Use upsert logic (check existence or just force put with specific ID if script allows, 
# but CouchDB requires _rev for updates. Easier to use task_utils helpers if available, 
# or just blindly try creating if missing.)

# Check if exists
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000003")
if [ "$HTTP_CODE" != "200" ]; then
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000003" \
        -H "Content-Type: application/json" \
        -d "$PATIENT_DOC" > /dev/null
    echo "Created patient Mei Lin Chen"
else
    echo "Patient Mei Lin Chen already exists"
fi

# 4. Ensure Admission Visit exists
echo "Ensuring admission visit exists..."
VISIT_DOC=$(cat <<EOF
{
  "data": {
    "patient": "patient_p1_000003",
    "visitType": "Admission",
    "startDate": "01/10/2025",
    "endDate": "",
    "examiner": "Dr. Sarah Lee",
    "location": "Surgical Ward",
    "reasonForVisit": "Symptomatic Cholelithiasis",
    "status": "admitted"
  }
}
EOF
)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000003")
if [ "$HTTP_CODE" != "200" ]; then
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000003" \
        -H "Content-Type: application/json" \
        -d "$VISIT_DOC" > /dev/null
    echo "Created admission visit"
else
    echo "Admission visit already exists"
fi

# 5. Prepare Browser
echo "Preparing Firefox..."
# Ensure logged in and fix any PouchDB sync issues
ensure_hospitalrun_logged_in
fix_offline_sync

# Wait for DB to be ready inside the app
wait_for_db_ready

# Navigate to Patient List to start
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="