#!/bin/bash
echo "=== Setting up order_diagnostic_workup task ==="

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

# Verify patient Elena Petrov exists (seeded as patient_p1_000011)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000011" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Elena Petrov..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000011" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00011",
            "displayName": "Petrov, Elena",
            "firstName": "Elena",
            "lastName": "Petrov",
            "sex": "Female",
            "dateOfBirth": "04/28/1969",
            "bloodType": "A+",
            "status": "Active",
            "address": "58 Chestnut Dr, Aurora, IL 60505",
            "phone": "630-555-0219",
            "email": "elena.petrov@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Clean up previous lab/imaging orders for Elena Petrov
echo "Cleaning up previous lab/imaging orders for Elena Petrov..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id in ['patient_p1_000011', 'visit_p1_000011']:
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_type = d.get('type', doc.get('type', ''))
    if 'patient_p1_000011' in patient_ref and doc_type in ['lab', 'imaging', 'lab-request', 'imaging-request']:
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

# Seed/verify outpatient visit for Elena Petrov
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000011" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Seeding outpatient visit for Elena Petrov..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000011" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000011",
            "visitType": "Outpatient",
            "startDate": "02/25/2026",
            "examiner": "Dr. Helen Bradley",
            "location": "Endocrinology Clinic",
            "reasonForVisit": "Thyroid disorder follow-up - hypothyroidism monitoring",
            "status": "current"
          }
        }' > /dev/null || true
fi

# Count baseline orders for Elena Petrov
INITIAL_ORDERS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    doc_type = d.get('type', doc.get('type', ''))
    if 'patient_p1_000011' in d.get('patient', '') and doc_type in ['lab', 'imaging', 'lab-request', 'imaging-request']:
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_ORDERS" > /tmp/initial_petrov_orders

date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

echo "Waiting for patient list..."
wait_for_db_ready

take_screenshot /tmp/order_diagnostic_workup_start.png
echo "Task start screenshot saved."

echo "=== order_diagnostic_workup setup complete ==="
echo "Agent sees: HospitalRun patients list"
echo "Task: Find Elena Petrov, order 2+ lab tests and 1+ imaging study within her visit"
