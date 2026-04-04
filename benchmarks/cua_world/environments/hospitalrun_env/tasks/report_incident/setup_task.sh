#!/bin/bash
echo "=== Setting up report_incident task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming (file creation checks)
date +%s > /tmp/task_start_time.txt

# 2. Apply offline sync fix to ensure app works
if type fix_offline_sync &>/dev/null; then
    fix_offline_sync
fi

# 3. Ensure HospitalRun is running
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 4. Ensure Patient "Maria Santos" exists
# The seed script usually creates 'patient_p1_20001' as Maria Santos.
# We check and re-seed if missing to guarantee task solvability.
PATIENT_CHECK=$(hr_couch_get "patient_p1_20001" | grep "Maria")

if [ -z "$PATIENT_CHECK" ]; then
    echo "Seeding patient Maria Santos..."
    hr_couch_put "patient_p1_20001" '{
      "data": {
        "friendlyId": "P20001",
        "displayName": "Santos, Maria",
        "firstName": "Maria",
        "lastName": "Santos",
        "sex": "Female",
        "dateOfBirth": "1965-05-12",
        "bloodType": "A+",
        "status": "Active",
        "address": "123 Ocean Drive, Miami, FL 33101",
        "phone": "305-555-0199",
        "email": "maria.santos@example.com",
        "patientType": "Inpatient",
        "type": "patient"
      }
    }'
fi

# 5. Record initial number of incident documents
# Used to verify a *new* document was actually created
INITIAL_COUNT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    grep -i "\"type\":\"incident\"" | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_incident_count.txt
echo "Initial incident count: $INITIAL_COUNT"

# 6. Prepare browser state
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in
wait_for_db_ready

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== setup_task.sh complete ==="