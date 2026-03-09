#!/bin/bash
set -e
echo "=== Setting up Correct Diagnosis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OSCAR to be ready
wait_for_oscar_http 300

# ============================================================
# 1. Ensure Patient Maria Garcia exists
# ============================================================
echo "Checking for patient Maria Garcia..."
PATIENT_ID=$(get_patient_id "Maria" "Garcia")

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Maria Garcia..."
    # Create patient with DOB 1985-03-15
    oscar_query "INSERT INTO demographic (last_name, first_name, year_of_birth, month_of_birth, date_of_birth, sex, patient_status, roster_status, lastUpdateDate) VALUES ('Garcia', 'Maria', '1985', '03', '15', 'F', 'AC', 'RO', NOW());"
    PATIENT_ID=$(get_patient_id "Maria" "Garcia")
fi
echo "Patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/patient_id.txt

# ============================================================
# 2. Seed the Incorrect Diagnosis (Essential Hypertension - 401)
# ============================================================
# Clean up any existing hypertension records for a clean state
echo "Cleaning existing records..."
oscar_query "DELETE FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND (dx_research_code='401' OR dx_research_code='405' OR diagnosis_desc LIKE '%Hypertension%');"

echo "Seeding incorrect diagnosis (401)..."
# Insert Essential Hypertension
# Status 'A' = Active
oscar_query "INSERT INTO dxresearch (demographic_no, dx_research_code, diagnosis_desc, status, start_date, update_date, coding_system) VALUES ('$PATIENT_ID', '401', 'Essential Hypertension', 'A', '2022-01-01', NOW(), 'icd9');"

# Record the ID of the seeded row for verification (to check if they updated or replaced)
INITIAL_DX_ID=$(oscar_query "SELECT id FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND dx_research_code='401' LIMIT 1")
echo "$INITIAL_DX_ID" > /tmp/initial_dx_id.txt
echo "Seeded diagnosis ID: $INITIAL_DX_ID"

# ============================================================
# 3. Setup Firefox
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Patient: Maria Garcia (ID: $PATIENT_ID)"
echo "Current Diagnosis: Essential Hypertension (401)"
echo "Goal: Change to Secondary Hypertension (405)"