#!/bin/bash
echo "=== Setting up inpatient_discharge task ==="

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

# Verify patient Arthur Jensen exists (seeded as patient_p1_000014)
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000014" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('firstName', ''))
" 2>/dev/null || echo "")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Arthur Jensen..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000014" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00014",
            "displayName": "Jensen, Arthur",
            "firstName": "Arthur",
            "lastName": "Jensen",
            "sex": "Male",
            "dateOfBirth": "11/03/1957",
            "bloodType": "O-",
            "status": "Active",
            "address": "17 Maple Rd, Rockford, IL 61101",
            "phone": "815-555-0274",
            "email": "arthur.jensen@example.com",
            "patientType": "Inpatient"
          }
        }' > /dev/null || true
fi

# Clean up previous task data for Arthur Jensen
echo "Cleaning up previous task data for Arthur Jensen..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id == 'patient_p1_000014' or doc_id == 'visit_p1_000014':
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    patient_ref = d.get('patient', doc.get('patient', ''))
    doc_type = d.get('type', doc.get('type', ''))
    if 'patient_p1_000014' in patient_ref and doc_type in ['vitals', 'diagnosis', 'medication']:
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

# Seed/verify inpatient visit for Arthur Jensen with status 'admitted' (not yet discharged)
VISIT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000014" 2>/dev/null | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('patient', ''))
" 2>/dev/null || echo "")

if [ -z "$VISIT_CHECK" ]; then
    echo "Seeding inpatient visit for Arthur Jensen..."
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000014" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "patient": "patient_p1_000014",
            "visitType": "Inpatient",
            "startDate": "02/20/2026",
            "examiner": "Dr. Samuel Okonkwo",
            "location": "Pulmonology Ward",
            "reasonForVisit": "COPD exacerbation with worsening dyspnea",
            "status": "admitted"
          }
        }' > /dev/null || true
else
    # Reset visit status to 'admitted' to ensure fresh discharge task
    REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000014" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_rev',''))" 2>/dev/null || echo "")
    if [ -n "$REV" ]; then
        curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/visit_p1_000014" \
            -H "Content-Type: application/json" \
            -d "{
              \"_rev\": \"$REV\",
              \"data\": {
                \"patient\": \"patient_p1_000014\",
                \"visitType\": \"Inpatient\",
                \"startDate\": \"02/20/2026\",
                \"examiner\": \"Dr. Samuel Okonkwo\",
                \"location\": \"Pulmonology Ward\",
                \"reasonForVisit\": \"COPD exacerbation with worsening dyspnea\",
                \"status\": \"admitted\"
              }
            }" > /dev/null || true
    fi
fi

# Record baseline
INITIAL_DOC_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    if 'patient_p1_000014' in json.dumps(row.get('doc', {})):
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_jensen_doc_count

date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

echo "Waiting for patient list..."
wait_for_db_ready

take_screenshot /tmp/inpatient_discharge_start.png
echo "Task start screenshot saved."

echo "=== inpatient_discharge setup complete ==="
echo "Agent sees: HospitalRun patients list"
echo "Task: Find Arthur Jensen, record vitals, add COPD diagnosis, add medication, check out patient"
