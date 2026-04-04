#!/bin/bash
echo "=== Setting up update_patient_and_schedule task ==="

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

# Seed/reset patient Robert Kowalski with OLD contact info so the agent must update it
echo "Seeding/resetting patient Robert Kowalski with outdated contact details..."
PATIENT_REV=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000006" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
print(doc.get('_rev', ''))
" 2>/dev/null || echo "")

if [ -n "$PATIENT_REV" ]; then
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000006" \
        -H "Content-Type: application/json" \
        -d "{
          \"_rev\": \"$PATIENT_REV\",
          \"data\": {
            \"friendlyId\": \"P00006\",
            \"displayName\": \"Kowalski, Robert\",
            \"firstName\": \"Robert\",
            \"lastName\": \"Kowalski\",
            \"sex\": \"Male\",
            \"dateOfBirth\": \"03/22/1971\",
            \"bloodType\": \"A-\",
            \"status\": \"Active\",
            \"address\": \"223 Oak Lane, Springfield, IL 62701\",
            \"phone\": \"217-555-0341\",
            \"email\": \"robert.kowalski@example.com\",
            \"patientType\": \"Outpatient\"
          }
        }" > /dev/null || true
else
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000006" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00006",
            "displayName": "Kowalski, Robert",
            "firstName": "Robert",
            "lastName": "Kowalski",
            "sex": "Male",
            "dateOfBirth": "03/22/1971",
            "bloodType": "A-",
            "status": "Active",
            "address": "223 Oak Lane, Springfield, IL 62701",
            "phone": "217-555-0341",
            "email": "robert.kowalski@example.com",
            "patientType": "Outpatient"
          }
        }' > /dev/null || true
fi

# Clean up any previous appointments for Robert Kowalski related to back pain follow-up
echo "Cleaning up previous back pain follow-up appointments for Robert Kowalski..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json, urllib.request, urllib.parse
data = json.load(sys.stdin)
couch_url = 'http://couchadmin:test@localhost:5984'
db = 'main'
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_id = row.get('id', '')
    if doc_id.startswith('_design') or doc_id == 'patient_p1_000006':
        continue
    d = doc.get('data', doc)
    doc_str = json.dumps(doc).lower()
    patient_ref = d.get('patient', doc.get('patient', ''))
    reason = d.get('reason', doc.get('reason', '')).lower()
    if 'patient_p1_000006' in patient_ref and 'back' in reason:
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

# Record baseline: save current phone and address for Robert Kowalski
BASELINE=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_000006" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
d = doc.get('data', doc)
print(d.get('phone', ''))
print(d.get('address', ''))
" 2>/dev/null || echo "")
echo "$BASELINE" > /tmp/initial_kowalski_contact

# Count baseline appointments for Robert Kowalski
INITIAL_APPT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    if 'patient_p1_000006' in d.get('patient', ''):
        count += 1
print(count)
" 2>/dev/null || echo "0")
echo "$INITIAL_APPT" > /tmp/initial_kowalski_appt_count

date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

echo "Waiting for patient list..."
wait_for_db_ready

take_screenshot /tmp/update_patient_and_schedule_start.png
echo "Task start screenshot saved."

echo "=== update_patient_and_schedule setup complete ==="
echo "Agent sees: HospitalRun patients list"
echo "Task: Find Robert Kowalski, update phone and address, then schedule back pain follow-up appointment"
