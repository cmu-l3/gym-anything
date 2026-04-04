#!/bin/bash
echo "=== Setting up emergency_triage_workup task ==="

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

# Verify patient Priya Sharma exists (seeded as patient_p1_000015)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000015" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Priya Sharma..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000015" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00015",
            "displayName": "Sharma, Priya",
            "firstName": "Priya",
            "lastName": "Sharma",
            "sex": "Female",
            "dateOfBirth": "07/09/1997",
            "bloodType": "A-",
            "status": "Active",
            "address": "405 Cedar Ln, Champaign, IL 61820",
            "phone": "217-555-0631",
            "email": "priya.sharma@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Clean up previous task data for Priya Sharma
echo "Cleaning up previous task data for Priya Sharma..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id in ['patient_p1_000015', 'visit_p1_000015']:
        continue
    d = doc.get('data', doc)
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_type = d.get('type', doc.get('type', ''))
    if 'patient_p1_000015' in patient_ref and doc_type in ['vitals', 'diagnosis', 'medication', 'lab', 'imaging', 'lab-request', 'imaging-request']:
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

# Seed/verify emergency visit for Priya Sharma (no vitals, no orders yet)
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000015" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Seeding emergency visit for Priya Sharma..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000015" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000015",
            "visitType": "Emergency",
            "startDate": "02/25/2026",
            "examiner": "Dr. Karen Walsh",
            "location": "Emergency Department",
            "reasonForVisit": "Acute right lower quadrant abdominal pain - rule out appendicitis",
            "status": "current"
          }
        }' > /dev/null || true
fi

# Record baseline
date +%s > /tmp/task_start_timestamp
INITIAL_DOC_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    if 'patient_p1_000015' in json.dumps(row.get('doc', {})):
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_sharma_doc_count

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

echo "Waiting for patient list..."
wait_for_db_ready

take_screenshot /tmp/emergency_triage_workup_start.png
echo "Task start screenshot saved."

echo "=== emergency_triage_workup setup complete ==="
echo "Agent sees: HospitalRun patients list"
echo "Task: Find Priya Sharma, record vitals, add appendicitis diagnosis, order labs and imaging"
