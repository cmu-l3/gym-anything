#!/bin/bash
set -e
echo "=== Setting up generate_admissions_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Output Directory
mkdir -p /home/ga/Desktop
# Remove any existing output file to ensure fresh creation
rm -f /home/ga/Desktop/admissions_report.png

# 3. Ensure HospitalRun is running and reachable
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 2
done

# 4. Ensure Data Exists (Seed a specific admission to guarantee report results)
# We add an admission visit for 'patient_p1_000001' (Margaret Chen) in 2020.
echo "Seeding historical admission data..."
VISIT_DOC=$(cat <<EOF
{
  "type": "visit",
  "visitType": "Inpatient",
  "patient": "patient_p1_000001",
  "startDate": "06/15/2020",
  "endDate": "06/20/2020",
  "reasonForVisit": "Pneumonia",
  "location": "Ward 1",
  "examiner": "Dr. Smith",
  "status": "discharged",
  "data": {
     "visitType": "Inpatient",
     "patient": "patient_p1_000001",
     "startDate": "06/15/2020",
     "endDate": "06/20/2020",
     "reasonForVisit": "Pneumonia",
     "status": "discharged"
  }
}
EOF
)
# Use the helper from task_utils to put data directly into CouchDB
# We give it a specific ID so we don't duplicate endlessly on retries
hr_couch_put "visit_p1_report_test_001" "$VISIT_DOC"

# 5. Fix PouchDB Sync Issue (Critical for HospitalRun stability)
fix_offline_sync

# 6. Prepare Firefox
# Kill existing firefox to start fresh
pkill -f firefox || true
sleep 1

# Launch Firefox and ensure logged in
# We start at the dashboard, NOT the reports page, to force navigation
echo "Launching Firefox..."
ensure_hospitalrun_logged_in

# 7. Wait for UI to settle
echo "Waiting for dashboard..."
wait_for_window "HospitalRun" 30
sleep 5

# 8. Take initial screenshot (evidence of starting state)
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="