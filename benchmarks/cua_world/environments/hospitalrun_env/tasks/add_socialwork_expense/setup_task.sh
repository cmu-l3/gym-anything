#!/bin/bash
set -e
echo "=== Setting up add_socialwork_expense task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure HospitalRun is accessible
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# Check if patient Maria Santos exists
echo "Checking for patient Maria Santos..."
PATIENT_EXISTS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for row in data.get('rows', []):
    doc = row.get('doc', {})
    fn = str(doc.get('firstName', '')).lower()
    ln = str(doc.get('lastName', '')).lower()
    data_field = doc.get('data', {})
    if isinstance(data_field, dict):
        fn = str(data_field.get('firstName', fn)).lower()
        ln = str(data_field.get('lastName', ln)).lower()
    
    if 'maria' in fn and 'santos' in ln:
        print('YES')
        sys.exit(0)
print('NO')
" 2>/dev/null || echo "UNKNOWN")

if [ "$PATIENT_EXISTS" != "YES" ]; then
    echo "Maria Santos not found, seeding patient..."
    # Create the patient document
    PATIENT_DOC=$(cat <<'ENDDOC'
{
    "_id": "patient_p1_00002",
    "data": {
        "firstName": "Maria",
        "lastName": "Santos",
        "sex": "Female",
        "dateOfBirth": "1978-08-22T00:00:00.000Z",
        "phone": "555-0142",
        "address": "456 Oak Avenue",
        "bloodType": "A+",
        "status": "Active",
        "patientType": "Outpatient"
    },
    "patientId": "p1_00002",
    "type": "patient"
}
ENDDOC
)
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_00002" \
        -H "Content-Type: application/json" \
        -d "$PATIENT_DOC" || true
    echo "Patient Maria Santos seeded."
else
    echo "Patient Maria Santos already exists."
fi

# Count existing social work/expense documents for baseline
# We look for documents that might be social work expenses to detect NEW ones later
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = 0
for row in data.get('rows', []):
    doc = row.get('doc', {})
    doc_str = json.dumps(doc).lower()
    # Broad check for expense-like documents
    if ('expense' in doc_str or 'social' in doc_str) and ('cost' in doc_str or 'amount' in doc_str):
        count += 1
print(count)
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_expense_count.txt
echo "Initial expense document count: $INITIAL_COUNT"

# Ensure Firefox is open and logged in
echo "Ensuring Firefox is ready..."
fix_offline_sync  # Apply fixes if needed
ensure_hospitalrun_logged_in
wait_for_db_ready

# Navigate to Patients list to start
navigate_firefox_to "http://localhost:3000/#/patients"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="