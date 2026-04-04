#!/bin/bash
echo "=== Setting up complete_outpatient_encounter task ==="

source /workspace/scripts/task_utils.sh

# Verify HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# Verify patient Grace Kim exists (seeded as patient_p1_000013)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000013" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Grace Kim..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000013" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00013",
            "displayName": "Kim, Grace",
            "firstName": "Grace",
            "lastName": "Kim",
            "sex": "Female",
            "dateOfBirth": "09/14/1976",
            "bloodType": "B+",
            "status": "Active",
            "address": "303 Birch Ave, Naperville, IL 60540",
            "phone": "630-555-0392",
            "email": "grace.kim@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Clean up any previous vitals/diagnosis/medication from this patient for this task
echo "Cleaning up previous task data for Grace Kim..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design'):
        continue
    doc_str = json.dumps(doc).lower()
    # Remove vitals, diagnoses, medications linked to Grace Kim from previous task runs
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_type = d.get('type', doc.get('type', ''))
    if 'patient_p1_000013' in patient_ref and doc_type in ['vitals', 'diagnosis', 'medication']:
        rev = doc.get('_rev', '')
        if rev:
            req = urllib.request.Request(
                f'{couch_url}/{db}/{doc_id}?rev={urllib.parse.quote(rev)}',
                method='DELETE'
            )
            try:
                urllib.request.urlopen(req, timeout=5)
            except:
                pass
" 2>/dev/null || true

# Seed/verify the outpatient visit for Grace Kim
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000013" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Seeding outpatient visit for Grace Kim..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000013" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000013",
            "visitType": "Outpatient",
            "startDate": "02/25/2026",
            "examiner": "Dr. Patricia Moore",
            "location": "Neurology Clinic",
            "reasonForVisit": "Chronic migraine follow-up",
            "status": "current"
          }
        }' > /dev/null || true
fi

# Record baseline: count docs linked to Grace Kim
INITIAL_DOC_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    if 'patient_p1_000013' in json.dumps(doc):
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_kim_doc_count

date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Wait for PouchDB to fully connect
echo "Waiting for patient list..."
wait_for_db_ready

# Take initial screenshot
take_screenshot /tmp/complete_outpatient_encounter_start.png
echo "Task start screenshot saved."

echo "=== complete_outpatient_encounter setup complete ==="
echo "Agent sees: HospitalRun patients list"
echo "Task: Find Grace Kim, complete her encounter (vitals + diagnosis + medication)"
