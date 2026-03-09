#!/bin/bash
echo "=== Setting up generate_diagnostic_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Apply the critical PouchDB loading fix (from env scripts)
# This prevents the infinite loading spinner by fixing auth/offline sync
fix_offline_sync

# 2. Verify HospitalRun is available
echo "Checking HospitalRun availability..."
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is available"
        break
    fi
    sleep 5
done

# 3. Seed Data: Create patients, visits, and diagnoses for Jan 2025
echo "Seeding diagnosis data..."

# Helper to put doc
put_doc() {
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/$1" \
        -H "Content-Type: application/json" \
        -d "$2" > /dev/null
}

# Seed Patient 1: Matías García Herrera
put_doc "patient_p1_d001" '{
  "data": {
    "friendlyId": "P001",
    "firstName": "Matías",
    "lastName": "García Herrera",
    "sex": "Male",
    "dateOfBirth": "1980-05-12",
    "patientType": "Outpatient"
  }
}'

# Seed Visit 1 (Jan 5)
put_doc "visit_p1_d001_v1" '{
  "data": {
    "patient": "patient_p1_d001",
    "visitType": "Outpatient",
    "startDate": "2025-01-05T10:00:00.000Z",
    "endDate": "2025-01-05T11:00:00.000Z",
    "status": "completed",
    "reasonForVisit": "Cough"
  }
}'

# Seed Diagnosis 1 (Pneumonia) linked to Visit 1
put_doc "diagnosis_p1_d001_v1_1" '{
  "data": {
    "diagnosis": "Pneumonia, unspecified organism (J18.9)",
    "date": "2025-01-05T10:30:00.000Z",
    "patient": "patient_p1_d001",
    "visit": "visit_p1_d001_v1",
    "active": true
  }
}'

# Seed Patient 2: Aisha Okonkwo-Williams
put_doc "patient_p1_d002" '{
  "data": {
    "friendlyId": "P002",
    "firstName": "Aisha",
    "lastName": "Okonkwo-Williams",
    "sex": "Female",
    "dateOfBirth": "1992-11-20",
    "patientType": "Outpatient"
  }
}'

# Seed Visit 2 (Jan 10)
put_doc "visit_p1_d002_v1" '{
  "data": {
    "patient": "patient_p1_d002",
    "visitType": "Outpatient",
    "startDate": "2025-01-10T14:00:00.000Z",
    "endDate": "2025-01-10T15:00:00.000Z",
    "status": "completed",
    "reasonForVisit": "Checkup"
  }
}'

# Seed Diagnosis 2 (Diabetes) linked to Visit 2
put_doc "diagnosis_p1_d002_v1_1" '{
  "data": {
    "diagnosis": "Type 2 diabetes mellitus without complications (E11.9)",
    "date": "2025-01-10T14:15:00.000Z",
    "patient": "patient_p1_d002",
    "visit": "visit_p1_d002_v1",
    "active": true
  }
}'

# Seed Patient 3: Dmitri Volkov-Petrov
put_doc "patient_p1_d003" '{
  "data": {
    "friendlyId": "P003",
    "firstName": "Dmitri",
    "lastName": "Volkov-Petrov",
    "sex": "Male",
    "dateOfBirth": "1975-03-30",
    "patientType": "Outpatient"
  }
}'

# Seed Visit 3 (Jan 15)
put_doc "visit_p1_d003_v1" '{
  "data": {
    "patient": "patient_p1_d003",
    "visitType": "Outpatient",
    "startDate": "2025-01-15T09:00:00.000Z",
    "endDate": "2025-01-15T09:30:00.000Z",
    "status": "completed",
    "reasonForVisit": "BP Check"
  }
}'

# Seed Diagnosis 3 (Hypertension) linked to Visit 3
put_doc "diagnosis_p1_d003_v1_1" '{
  "data": {
    "diagnosis": "Essential (primary) hypertension (I10)",
    "date": "2025-01-15T09:15:00.000Z",
    "patient": "patient_p1_d003",
    "visit": "visit_p1_d003_v1",
    "active": true
  }
}'

# 4. Prepare Application State
echo "Ensuring Firefox is ready..."
ensure_hospitalrun_logged_in

# Navigate to dashboard to start
navigate_firefox_to "http://localhost:3000"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="