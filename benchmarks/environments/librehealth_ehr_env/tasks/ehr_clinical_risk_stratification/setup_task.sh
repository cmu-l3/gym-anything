#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== ehr_clinical_risk_stratification setup ==="

chmod +x /workspace/tasks/ehr_clinical_risk_stratification/export_result.sh 2>/dev/null || true

wait_for_librehealth 120

TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/lh_task_start
echo "Task started at: $(date)"

# Pick 2 NHANES patients for risk stratification (use very high offsets)
P1_PID=$(librehealth_query "SELECT pid FROM patient_data WHERE pid NOT IN (2,782,8471) AND fname IS NOT NULL AND fname != '' AND lname IS NOT NULL ORDER BY pid LIMIT 1 OFFSET 350" 2>/dev/null | tr -d '[:space:]')
P2_PID=$(librehealth_query "SELECT pid FROM patient_data WHERE pid NOT IN (2,782,8471,${P1_PID}) AND fname IS NOT NULL AND fname != '' AND lname IS NOT NULL ORDER BY pid LIMIT 1 OFFSET 420" 2>/dev/null | tr -d '[:space:]')

P1_FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid=${P1_PID}" 2>/dev/null | tr -d '[:space:]')
P1_LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid=${P1_PID}" 2>/dev/null | tr -d '[:space:]')
P1_DOB=$(librehealth_query "SELECT DOB FROM patient_data WHERE pid=${P1_PID}" 2>/dev/null | tr -d '[:space:]')

P2_FNAME=$(librehealth_query "SELECT fname FROM patient_data WHERE pid=${P2_PID}" 2>/dev/null | tr -d '[:space:]')
P2_LNAME=$(librehealth_query "SELECT lname FROM patient_data WHERE pid=${P2_PID}" 2>/dev/null | tr -d '[:space:]')
P2_DOB=$(librehealth_query "SELECT DOB FROM patient_data WHERE pid=${P2_PID}" 2>/dev/null | tr -d '[:space:]')

echo "P1: ${P1_FNAME} ${P1_LNAME} (PID:${P1_PID})"
echo "P2: ${P2_FNAME} ${P2_LNAME} (PID:${P2_PID})"

P1_DISP=$(date -d "$P1_DOB" '+%m/%d/%Y' 2>/dev/null || echo "$P1_DOB")
P2_DISP=$(date -d "$P2_DOB" '+%m/%d/%Y' 2>/dev/null || echo "$P2_DOB")

# Record baseline counts (BEFORE agent acts)
P1_INIT_PROBS=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid=${P1_PID} AND type='medical_problem'" 2>/dev/null | tr -d '[:space:]')
P2_INIT_PROBS=$(librehealth_query "SELECT COUNT(*) FROM lists WHERE pid=${P2_PID} AND type='medical_problem'" 2>/dev/null | tr -d '[:space:]')
P1_INIT_APPTS=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=${P1_PID}" 2>/dev/null | tr -d '[:space:]')
P2_INIT_APPTS=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=${P2_PID}" 2>/dev/null | tr -d '[:space:]')

# Risk factors assigned (unique enough to verify)
P1_RISK_PROB="High Cardiovascular Risk - ASCVD 10-Year Score Greater Than 20 Percent"
P2_RISK_PROB="Uncontrolled Type 2 Diabetes - HbA1c Above 9 Percent Requiring Intensification"

# Write temp files
echo "$P1_PID"        > /tmp/.rs_p1_pid
echo "$P1_FNAME"      > /tmp/.rs_p1_fname
echo "$P1_LNAME"      > /tmp/.rs_p1_lname
echo "$P1_DOB"        > /tmp/.rs_p1_dob
echo "$P1_INIT_PROBS" > /tmp/.rs_p1_init_probs
echo "$P1_INIT_APPTS" > /tmp/.rs_p1_init_appts
echo "$P2_PID"        > /tmp/.rs_p2_pid
echo "$P2_FNAME"      > /tmp/.rs_p2_fname
echo "$P2_LNAME"      > /tmp/.rs_p2_lname
echo "$P2_DOB"        > /tmp/.rs_p2_dob
echo "$P2_INIT_PROBS" > /tmp/.rs_p2_init_probs
echo "$P2_INIT_APPTS" > /tmp/.rs_p2_init_appts

# Write GT JSON
python3 << 'PYEOF'
import json

gt = {
    "task_start": int(open('/tmp/lh_task_start').read().strip()),
    "patients": [
        {
            "pid":          int(open('/tmp/.rs_p1_pid').read().strip()),
            "fname":        open('/tmp/.rs_p1_fname').read().strip(),
            "lname":        open('/tmp/.rs_p1_lname').read().strip(),
            "dob":          open('/tmp/.rs_p1_dob').read().strip(),
            "init_probs":   int(open('/tmp/.rs_p1_init_probs').read().strip() or '0'),
            "init_appts":   int(open('/tmp/.rs_p1_init_appts').read().strip() or '0'),
            "risk_problem": "High Cardiovascular Risk - ASCVD 10-Year Score Greater Than 20 Percent",
            "risk_keyword": "cardiovascular risk",
            "appt_type":    "Office Visit",
            "risk_score":   "32%",
            "condition":    "Cardiovascular Disease Risk"
        },
        {
            "pid":          int(open('/tmp/.rs_p2_pid').read().strip()),
            "fname":        open('/tmp/.rs_p2_fname').read().strip(),
            "lname":        open('/tmp/.rs_p2_lname').read().strip(),
            "dob":          open('/tmp/.rs_p2_dob').read().strip(),
            "init_probs":   int(open('/tmp/.rs_p2_init_probs').read().strip() or '0'),
            "init_appts":   int(open('/tmp/.rs_p2_init_appts').read().strip() or '0'),
            "risk_problem": "Uncontrolled Type 2 Diabetes - HbA1c Above 9 Percent Requiring Intensification",
            "risk_keyword": "uncontrolled type 2 diabetes",
            "appt_type":    "Office Visit",
            "risk_score":   "HbA1c 11.2%",
            "condition":    "Uncontrolled Diabetes"
        }
    ]
}
with open('/tmp/lh_risk_gt.json', 'w') as f:
    json.dump(gt, f, indent=2)
print("GT written: /tmp/lh_risk_gt.json")
PYEOF

# Create companion document
mkdir -p /home/ga/Documents
TODAY=$(date '+%B %d, %Y')
FOLLOWUP=$(date -d "+14 days" '+%B %d, %Y')
YEAR=$(date '+%Y')

cat > /home/ga/Documents/risk_stratification_report.txt << DOCEOF
CLINICAL RISK STRATIFICATION REPORT
Population Health Management Program
Report Date: ${TODAY}
Prepared by: Population Health Analytics Team

This report identifies high-risk patients requiring immediate care management
outreach. For each patient, you must complete TWO actions in LibreHealth EHR:

  ACTION 1: Add the specified clinical risk factor to their Medical Problem List
  ACTION 2: Schedule a follow-up appointment (type: Office Visit) with provider admin

Both actions are required for each patient to satisfy care management protocols.

=========================================================================
PATIENT 1 — TIER 1 HIGH RISK
=========================================================================
Patient Name: ${P1_FNAME} ${P1_LNAME}
Date of Birth: ${P1_DISP}

Risk Assessment Summary:
  Risk Stratification Tier: Tier 1 — High Risk
  Primary Risk Driver: Elevated cardiovascular disease (CVD) risk score
  ASCVD 10-Year Risk Score: 32% (High Risk threshold: >20%)
  Supporting Data: Hypertension (uncontrolled), Hyperlipidemia, current smoker,
                   BMI 31.4, family history of MI before age 60

REQUIRED ACTIONS IN LibreHealth EHR:

  ACTION 1 — ADD MEDICAL PROBLEM:
    Title: High Cardiovascular Risk - ASCVD 10-Year Score Greater Than 20 Percent
    ICD Code: Z82.49
    Status: Active
    Notes: Patient stratified as Tier 1 High Risk. Cardiology referral warranted.

  ACTION 2 — SCHEDULE APPOINTMENT:
    Appointment Type: Office Visit
    Purpose: Cardiovascular risk reduction counseling and statin therapy review
    Suggested Date: ${FOLLOWUP}
    Provider: admin
    Duration: 30 minutes

=========================================================================
PATIENT 2 — TIER 1 HIGH RISK
=========================================================================
Patient Name: ${P2_FNAME} ${P2_LNAME}
Date of Birth: ${P2_DISP}

Risk Assessment Summary:
  Risk Stratification Tier: Tier 1 — High Risk
  Primary Risk Driver: Poorly controlled Type 2 Diabetes
  Most Recent HbA1c: 11.2% (target: <7%, poor control threshold: >9%)
  Supporting Data: No documented HbA1c in 14 months prior to this result;
                   patient missing 3 consecutive diabetes management visits;
                   BMI 36.2; hypertension comorbidity

REQUIRED ACTIONS IN LibreHealth EHR:

  ACTION 1 — ADD MEDICAL PROBLEM:
    Title: Uncontrolled Type 2 Diabetes - HbA1c Above 9 Percent Requiring Intensification
    ICD Code: E11.65
    Status: Active
    Notes: HbA1c 11.2%. Medication intensification and endocrinology referral required.

  ACTION 2 — SCHEDULE APPOINTMENT:
    Appointment Type: Office Visit
    Purpose: Diabetes management intensification — medication review and titration
    Suggested Date: ${FOLLOWUP}
    Provider: admin
    Duration: 45 minutes

=========================================================================
Both patients require outreach within 5 business days of this report.
Contact the Population Health team at ext. 5500 with questions.
=========================================================================
DOCEOF

echo "Companion document written: /home/ga/Documents/risk_stratification_report.txt"

DISPLAY=:1 scrot /tmp/lh_risk_start.png 2>/dev/null || true
restart_firefox "http://localhost:8000/interface/patient_file/patient_select.php"

echo "=== ehr_clinical_risk_stratification setup complete ==="
exit 0
