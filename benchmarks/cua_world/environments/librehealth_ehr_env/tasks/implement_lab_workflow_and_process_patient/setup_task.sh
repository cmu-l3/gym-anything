#!/bin/bash
echo "=== Setting up Implement Lab Workflow Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 120

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/lh_lab_workflow_gt.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Record task start time
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt
echo "Task start timestamp: $TASK_START"

# ---- Select a deterministic NHANES patient (OFFSET 500 to avoid collisions) ----
P_PID=$(librehealth_query "SELECT pid FROM patient_data WHERE pid > 0 AND fname IS NOT NULL AND fname != '' AND lname IS NOT NULL AND lname != '' ORDER BY pid LIMIT 1 OFFSET 500" 2>/dev/null | tr -d '[:space:]')
P_FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid=${P_PID}" 2>/dev/null | tr -d '[:space:]')
P_LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid=${P_PID}" 2>/dev/null | tr -d '[:space:]')
P_DOB=$(librehealth_query "SELECT DOB FROM patient_data WHERE pid=${P_PID}" 2>/dev/null | tr -d '[:space:]')

echo "Selected patient: ${P_FNAME} ${P_LNAME} (PID: ${P_PID}, DOB: ${P_DOB})"

# ---- Record baselines for anti-gaming ----
BASELINE_PT_ID=$(librehealth_query "SELECT COALESCE(MAX(procedure_type_id),0) FROM procedure_type" 2>/dev/null | tr -d '[:space:]')
BASELINE_PO_COUNT=$(librehealth_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${P_PID}" 2>/dev/null | tr -d '[:space:]')
BASELINE_PROB_COUNT=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid=${P_PID} AND type='medical_problem'" 2>/dev/null | tr -d '[:space:]')
BASELINE_RX_COUNT=$(librehealth_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${P_PID}" 2>/dev/null | tr -d '[:space:]')
BASELINE_APPT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM libreehr_postcalendar_events WHERE pc_pid=${P_PID}" 2>/dev/null | tr -d '[:space:]')

# Default to 0 if empty
BASELINE_PT_ID=${BASELINE_PT_ID:-0}
BASELINE_PO_COUNT=${BASELINE_PO_COUNT:-0}
BASELINE_PROB_COUNT=${BASELINE_PROB_COUNT:-0}
BASELINE_RX_COUNT=${BASELINE_RX_COUNT:-0}
BASELINE_APPT_COUNT=${BASELINE_APPT_COUNT:-0}

echo "Baselines: PT_ID=${BASELINE_PT_ID} PO=${BASELINE_PO_COUNT} PROB=${BASELINE_PROB_COUNT} RX=${BASELINE_RX_COUNT} APPT=${BASELINE_APPT_COUNT}"

# ---- Clean up any previous attempts (idempotent) ----
librehealth_query "DELETE FROM procedure_type WHERE name IN ('Endocrine Panel', 'Hemoglobin A1c', 'HbA1c Percentage', 'Estimated Average Glucose') AND procedure_type_id > ${BASELINE_PT_ID}" 2>/dev/null || true

# ---- Compute follow-up date (3 months from today) ----
FOLLOWUP_DATE=$(date -d "+3 months" '+%Y-%m-%d' 2>/dev/null || echo "2026-06-20")
FOLLOWUP_DISPLAY=$(date -d "+3 months" '+%B %d, %Y' 2>/dev/null || echo "June 20, 2026")
P_DOB_DISPLAY=$(date -d "$P_DOB" '+%m/%d/%Y' 2>/dev/null || echo "$P_DOB")

# ---- Write companion document to Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lab_order_request.txt << DOCEOF
================================================================================
                    IN-HOUSE HbA1c LAB ORDER REQUEST
                    Family Practice Clinical Workflow
================================================================================

Date: $(date '+%B %d, %Y')
Prepared by: Clinical Operations Manager

BACKGROUND:
The practice has acquired a new in-house HbA1c point-of-care analyzer. Before
processing patient samples, the test must be configured in the EHR system.
This document contains all the details needed to set up and execute the first
lab test.

================================================================================
PART 1: PROCEDURE CONFIGURATION (EHR Administration)
================================================================================

Navigate to the Procedure Configuration section in Administration and create
the following hierarchy:

  ORDER GROUP:
    Name:           Endocrine Panel

  PROCEDURE ORDER (under Endocrine Panel):
    Name:           Hemoglobin A1c
    Procedure Code: 83036
    Standard Code:  CPT4:83036

  DISCRETE RESULTS (under Hemoglobin A1c):

    1. Name: HbA1c Percentage
       Units: %
       Normal Range: 4.0 - 6.0

    2. Name: Estimated Average Glucose
       Units: mg/dL

================================================================================
PART 2: LAB ORDER PROCESSING
================================================================================

PATIENT INFORMATION:
  Full Name:       ${P_FNAME} ${P_LNAME}
  Date of Birth:   ${P_DOB_DISPLAY}
  Patient ID:      ${P_PID}

INSTRUCTIONS:
  1. Open the patient's chart
  2. Create a new encounter (Office Visit)
  3. Place a lab order for the Hemoglobin A1c test configured above
  4. Enter the following results:

     HbA1c:                     7.8 %
     Estimated Average Glucose: 177 mg/dL
     Report Status:             Final

================================================================================
PART 3: CLINICAL FOLLOW-UP (Abnormal Result Protocol)
================================================================================

The HbA1c result of 7.8% exceeds the 7.0% treatment initiation threshold.
Per the practice's diabetes management protocol, complete the following:

  1. DIAGNOSIS:
     Add to Problem List: Uncontrolled Type 2 Diabetes
     ICD-10 Code:         E11.65
     Status:              Active

  2. PRESCRIPTION:
     Drug:       Metformin 500mg tablets
     Directions: Take one tablet by mouth twice daily with meals
     Quantity:   60
     Refills:    3

  3. FOLLOW-UP APPOINTMENT:
     Type:     Office Visit
     Date:     ${FOLLOWUP_DISPLAY}
     Time:     2:00 PM
     Provider: admin
     Purpose:  Diabetes management review and HbA1c recheck

================================================================================
All actions must be completed in LibreHealth EHR.
Login credentials: admin / password
================================================================================
DOCEOF

chown ga:ga /home/ga/Desktop/lab_order_request.txt
echo "Companion document written to /home/ga/Desktop/lab_order_request.txt"

# ---- Write ground truth JSON for verification ----
python3 << PYEOF
import json

gt = {
    "task_start": ${TASK_START},
    "patient": {
        "pid": ${P_PID},
        "fname": "${P_FNAME}",
        "lname": "${P_LNAME}",
        "dob": "${P_DOB}"
    },
    "baselines": {
        "max_procedure_type_id": ${BASELINE_PT_ID},
        "procedure_order_count": ${BASELINE_PO_COUNT},
        "problems_count": ${BASELINE_PROB_COUNT},
        "prescriptions_count": ${BASELINE_RX_COUNT},
        "appointments_count": ${BASELINE_APPT_COUNT}
    },
    "expected": {
        "group_name": "Endocrine Panel",
        "order_name": "Hemoglobin A1c",
        "cpt_code": "83036",
        "standard_code": "CPT4:83036",
        "result_types": [
            {"name": "HbA1c Percentage", "units": "%", "range": "4.0-6.0"},
            {"name": "Estimated Average Glucose", "units": "mg/dL"}
        ],
        "hba1c_value": 7.8,
        "eag_value": 177,
        "diagnosis_keyword": "diabetes",
        "icd_code": "E11.65",
        "drug_keyword": "metformin",
        "followup_date": "${FOLLOWUP_DATE}"
    }
}

with open("/tmp/lh_lab_workflow_gt.json", "w") as f:
    json.dump(gt, f, indent=2)
print("Ground truth written to /tmp/lh_lab_workflow_gt.json")
PYEOF

# ---- Launch Firefox at login page ----
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Implement Lab Workflow Task Setup Complete ==="
