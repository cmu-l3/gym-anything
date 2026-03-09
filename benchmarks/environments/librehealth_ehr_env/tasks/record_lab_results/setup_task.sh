#!/bin/bash
echo "=== Setting up Record Lab Results Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is ready
wait_for_librehealth 120

# ------------------------------------------------------------------
# 1. SETUP PATIENT
# ------------------------------------------------------------------
# We need Jannette Charley. Check if she exists in NHANES data.
# If not, create her.
echo "Checking for patient Jannette Charley..."
PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Jannette' AND lname='Charley' LIMIT 1")

if [ -z "$PID" ]; then
    echo "Patient not found, creating..."
    # Insert basic patient record
    librehealth_query "INSERT INTO patient_data (fname, lname, DOB, sex, street, city, state, postal_code, country_code) 
                       VALUES ('Jannette', 'Charley', '1965-02-14', 'Female', '123 Test Ln', 'TestCity', 'TS', '12345', 'US')"
    PID=$(librehealth_query "SELECT pid FROM patient_data WHERE fname='Jannette' AND lname='Charley' LIMIT 1")
fi
echo "Using Patient PID: $PID"
echo "$PID" > /tmp/target_pid.txt

# Create an encounter for today (required to link orders)
ENC_DATE=$(date +%Y-%m-%d)
librehealth_query "INSERT INTO form_encounter (date, reason, pid, encounter) VALUES ('$ENC_DATE 09:00:00', 'Lab Work', '$PID', '5000')"
ENCOUNTER_ID="5000"

# ------------------------------------------------------------------
# 2. SETUP PROCEDURE HIERARCHY (Lab -> Order -> Results)
# ------------------------------------------------------------------
# We use high IDs to avoid conflicts with existing NHANES data

# Root: Laboratory
LAB_ID=50000
librehealth_query "DELETE FROM procedure_type WHERE procedure_type_id >= 50000"
librehealth_query "INSERT INTO procedure_type (procedure_type_id, parent, name, lab_id, procedure_code, procedure_type) 
                   VALUES ($LAB_ID, 0, 'General Hospital Lab', 0, 'LAB01', 'group')"

# Order: CBC
ORDER_TYPE_ID=50001
librehealth_query "INSERT INTO procedure_type (procedure_type_id, parent, name, lab_id, procedure_code, procedure_type) 
                   VALUES ($ORDER_TYPE_ID, $LAB_ID, 'Complete Blood Count', $LAB_ID, 'CBC', 'order')"

# Results: WBC, RBC, Hgb, Hct, Platelets
# Standard codes (LOINC-like) help verification but names are key for UI
librehealth_query "INSERT INTO procedure_type (procedure_type_id, parent, name, lab_id, procedure_code, procedure_type, units, range) VALUES 
(50002, $ORDER_TYPE_ID, 'WBC', $LAB_ID, 'WBC', 'result', '10*3/uL', '4.5-11.0'),
(50003, $ORDER_TYPE_ID, 'RBC', $LAB_ID, 'RBC', 'result', '10*6/uL', '3.80-5.10'),
(50004, $ORDER_TYPE_ID, 'Hemoglobin', $LAB_ID, 'HGB', 'result', 'g/dL', '12.0-16.0'),
(50005, $ORDER_TYPE_ID, 'Hematocrit', $LAB_ID, 'HCT', 'result', '%', '36.0-46.0'),
(50006, $ORDER_TYPE_ID, 'Platelet Count', $LAB_ID, 'PLT', 'result', '10*3/uL', '150-400')"

# ------------------------------------------------------------------
# 3. CREATE PENDING ORDER
# ------------------------------------------------------------------
# Create the order linked to the patient and encounter
ORDER_ID=50001
librehealth_query "DELETE FROM procedure_order WHERE procedure_order_id = $ORDER_ID"
librehealth_query "INSERT INTO procedure_order (procedure_order_id, provider_id, patient_id, encounter_id, date_ordered, procedure_type_id, order_status) 
                   VALUES ($ORDER_ID, 1, $PID, $ENCOUNTER_ID, '$ENC_DATE 09:15:00', $ORDER_TYPE_ID, 'pending')"

echo "Created Pending Order #$ORDER_ID for Patient #$PID"

# ------------------------------------------------------------------
# 4. LAUNCH UI
# ------------------------------------------------------------------
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="