#!/bin/bash
# Setup script for Pre-Operative Medication Review Task
# Creates patient Margaret Chen with complex comorbidities and polypharmacy,
# then sets up the environment for a pre-operative clearance assessment.

echo "=== Setting up Pre-Operative Medication Review Task ==="

source /workspace/scripts/task_utils.sh

PATIENT_FNAME="Margaret"
PATIENT_LNAME="Chen"
PATIENT_DOB="1962-08-15"

# --- Clean stale outputs from prior runs ---
rm -f /tmp/preop_review_result.json
rm -f /tmp/initial_rx_count /tmp/initial_enc_count /tmp/initial_vitals_count
rm -f /tmp/initial_lab_count /tmp/initial_note_count
rm -f /tmp/task_patient_pid /tmp/task_start_timestamp

# --- Record task start timestamp (anti-gaming) ---
date +%s > /tmp/task_start_timestamp
date +%Y-%m-%d > /tmp/task_start_date
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# --- Check / create patient ---
PATIENT_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='${PATIENT_FNAME}' AND lname='${PATIENT_LNAME}' AND DOB='${PATIENT_DOB}' LIMIT 1;" 2>/dev/null | tr -d ' \t\n\r' || echo "")

if [ -z "$PATIENT_PID" ] || ! echo "$PATIENT_PID" | grep -qE '^[0-9]+$'; then
    echo "Creating patient ${PATIENT_FNAME} ${PATIENT_LNAME}..."
    MAX_PID=$(openemr_query "SELECT COALESCE(MAX(pid),0) FROM patient_data;" 2>/dev/null | tr -d ' \t\n\r' || echo "100")
    NEW_PID=$((MAX_PID + 1))
    openemr_query "INSERT INTO patient_data (pid, pubpid, fname, lname, DOB, sex, ss, street, city, state, postal_code, phone_home, status, race, ethnicity, language, providerID, date, regdate)
        VALUES (${NEW_PID}, 'PT-$(printf '%05d' ${NEW_PID})', '${PATIENT_FNAME}', '${PATIENT_LNAME}', '${PATIENT_DOB}', 'Female', '234-56-7890',
                '45 Maple Street', 'Springfield', 'MA', '01103', '555-014-2836', 'married',
                'white', 'not_hisp_or_latino', 'English', 1, NOW(), NOW());"
    PATIENT_PID="$NEW_PID"
    echo "Created patient PID: ${PATIENT_PID}"
else
    echo "Patient exists with PID: ${PATIENT_PID}"
fi

echo "$PATIENT_PID" > /tmp/task_patient_pid

# --- Clean up existing conditions and medications from prior runs ---
openemr_query "DELETE FROM lists WHERE pid=${PATIENT_PID} AND type='medical_problem' AND title IN ('Essential hypertension','Type 2 diabetes mellitus','Atrial fibrillation','Osteoarthritis of hip','Gastroesophageal reflux disease','Chronic kidney disease stage 2');" 2>/dev/null || true
openemr_query "DELETE FROM lists WHERE pid=${PATIENT_PID} AND type='allergy' AND title IN ('Allergy to penicillin','Allergy to sulfonamide');" 2>/dev/null || true
openemr_query "DELETE FROM prescriptions WHERE patient_id=${PATIENT_PID} AND drug IN ('Warfarin 5 MG Oral Tablet','Clopidogrel 75 MG Oral Tablet','Ibuprofen 400 MG Oral Tablet','Metformin 1000 MG Oral Tablet','Lisinopril 20 MG Oral Tablet','Amlodipine 10 MG Oral Tablet','Atorvastatin 40 MG Oral Tablet','Omeprazole 20 MG Oral Capsule');" 2>/dev/null || true

# --- Insert active conditions ---
echo "Inserting medical conditions..."
openemr_query "INSERT INTO lists (pid, type, title, begdate, enddate, outcome, diagnosis) VALUES
    (${PATIENT_PID}, 'medical_problem', 'Essential hypertension', '2005-03-15', NULL, 0, 'SNOMED-CT:59621000'),
    (${PATIENT_PID}, 'medical_problem', 'Type 2 diabetes mellitus', '2010-08-22', NULL, 0, 'SNOMED-CT:44054006'),
    (${PATIENT_PID}, 'medical_problem', 'Atrial fibrillation', '2018-11-03', NULL, 0, 'SNOMED-CT:49436004'),
    (${PATIENT_PID}, 'medical_problem', 'Osteoarthritis of hip', '2019-06-15', NULL, 0, 'SNOMED-CT:239873007'),
    (${PATIENT_PID}, 'medical_problem', 'Gastroesophageal reflux disease', '2012-04-10', NULL, 0, 'SNOMED-CT:235595009'),
    (${PATIENT_PID}, 'medical_problem', 'Chronic kidney disease stage 2', '2021-09-01', NULL, 0, 'SNOMED-CT:431856006');" 2>/dev/null
echo "Inserted 6 medical conditions"

# --- Insert allergies ---
echo "Inserting allergies..."
openemr_query "INSERT INTO lists (pid, type, title, begdate, enddate, outcome, diagnosis) VALUES
    (${PATIENT_PID}, 'allergy', 'Allergy to penicillin', '1975-01-01', NULL, 0, 'SNOMED-CT:91936005'),
    (${PATIENT_PID}, 'allergy', 'Allergy to sulfonamide', '1990-06-15', NULL, 0, 'SNOMED-CT:294499002');" 2>/dev/null
echo "Inserted 2 allergies"

# --- Insert 3 historical encounters ---
echo "Inserting historical encounters..."
FACILITY_ID=$(openemr_query "SELECT id FROM facility ORDER BY id LIMIT 1;" 2>/dev/null | tr -d ' \t\n\r' || echo "3")
openemr_query "INSERT INTO form_encounter (date, reason, facility, facility_id, pid, encounter, onset_date, provider_id)
    VALUES ('2023-06-15 09:00:00', 'Annual wellness visit', 'Springfield Medical Center', ${FACILITY_ID}, ${PATIENT_PID}, FLOOR(RAND()*900000+100000), '2023-06-15', 1);" 2>/dev/null || true
openemr_query "INSERT INTO form_encounter (date, reason, facility, facility_id, pid, encounter, onset_date, provider_id)
    VALUES ('2024-01-22 10:30:00', 'Atrial fibrillation follow-up', 'Springfield Medical Center', ${FACILITY_ID}, ${PATIENT_PID}, FLOOR(RAND()*900000+100000), '2024-01-22', 1);" 2>/dev/null || true
openemr_query "INSERT INTO form_encounter (date, reason, facility, facility_id, pid, encounter, onset_date, provider_id)
    VALUES ('2024-09-10 14:00:00', 'Hip pain evaluation - surgical referral', 'Springfield Medical Center', ${FACILITY_ID}, ${PATIENT_PID}, FLOOR(RAND()*900000+100000), '2024-09-10', 1);" 2>/dev/null || true
echo "Inserted 3 historical encounters"

# --- Insert 8 active medications ---
echo "Inserting medications..."
PRESCRIBER_ID=1

python3 << 'PYEOF'
import subprocess, sys

pid = int(open('/tmp/task_patient_pid').read().strip())
prescriber = 1

meds = [
    ("Warfarin 5 MG Oral Tablet",        "Anticoagulation for atrial fibrillation"),
    ("Clopidogrel 75 MG Oral Tablet",    "Antiplatelet therapy"),
    ("Ibuprofen 400 MG Oral Tablet",     "Pain management for osteoarthritis"),
    ("Metformin 1000 MG Oral Tablet",    "Type 2 diabetes management"),
    ("Lisinopril 20 MG Oral Tablet",     "Hypertension and renal protection"),
    ("Amlodipine 10 MG Oral Tablet",     "Hypertension - calcium channel blocker"),
    ("Atorvastatin 40 MG Oral Tablet",   "Hyperlipidemia management"),
    ("Omeprazole 20 MG Oral Capsule",    "GERD - proton pump inhibitor"),
]

cols = ("patient_id, date_added, provider_id, drug, refills, note, active, "
        "txDate, usage_category_title, request_intent_title")

inserted = 0
for drug, note in meds:
    sql = ("INSERT INTO prescriptions (" + cols + ") VALUES ("
           + str(pid) + ", NOW(), " + str(prescriber) + ", "
           + "'" + drug + "', 5, '" + note + "', 1, CURDATE(), '', '');")
    result = subprocess.run(
        ["docker", "exec", "openemr-mysql", "mysql",
         "-u", "openemr", "-popenemr", "openemr", "-N", "-e", sql],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        inserted += 1
        print("  OK: " + drug)
    else:
        print("  WARN: insert failed for " + drug + ": " + result.stderr.strip(), file=sys.stderr)

print("Inserted " + str(inserted) + "/8 medications for PID " + str(pid))
sys.exit(0 if inserted == 8 else 1)
PYEOF
RX_INSERT_EXIT=$?
[ $RX_INSERT_EXIT -eq 0 ] && echo "All 8 medications inserted OK" || echo "WARN: Some medication inserts may have failed (exit $RX_INSERT_EXIT)"

# --- Record initial state for delta detection ---
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1;" 2>/dev/null | tr -d ' \t\n\r' || echo "8")
echo "${INITIAL_RX_COUNT:-8}" > /tmp/initial_rx_count

INITIAL_ENC_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_encounter WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "3")
echo "${INITIAL_ENC_COUNT:-3}" > /tmp/initial_enc_count

INITIAL_VITALS_COUNT=$(openemr_query "SELECT COUNT(*) FROM form_vitals WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
echo "${INITIAL_VITALS_COUNT:-0}" > /tmp/initial_vitals_count

INITIAL_LAB_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
echo "${INITIAL_LAB_COUNT:-0}" > /tmp/initial_lab_count

INITIAL_NOTE_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
echo "${INITIAL_NOTE_COUNT:-0}" > /tmp/initial_note_count

echo "Baseline: rx=${INITIAL_RX_COUNT} enc=${INITIAL_ENC_COUNT} vitals=${INITIAL_VITALS_COUNT} labs=${INITIAL_LAB_COUNT} notes=${INITIAL_NOTE_COUNT}"

# --- Launch Firefox with OpenEMR ---
OPENEMR_LOGIN_URL="http://localhost/interface/login/login.php?site=default"

pkill -u ga -f firefox 2>/dev/null || true
sleep 3

echo "Waiting for OpenEMR to respond..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${OPENEMR_LOGIN_URL}" 2>/dev/null || echo "000")
    [ "$HTTP_CODE" = "200" ] && echo "OpenEMR ready (HTTP ${HTTP_CODE})" && break
    echo "  OpenEMR not ready yet (HTTP ${HTTP_CODE}), waiting..."
    sleep 5
done

su - ga -c "DISPLAY=:1 firefox '${OPENEMR_LOGIN_URL}' > /tmp/firefox_openemr.log 2>&1 &"
sleep 8

WID=$(get_firefox_window_id 2>/dev/null || echo "")
if [ -n "$WID" ]; then
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot "/tmp/preop_review_start.png" || true

echo ""
echo "=== Setup Complete ==="
echo "Patient: ${PATIENT_FNAME} ${PATIENT_LNAME} (DOB: ${PATIENT_DOB}) | PID: ${PATIENT_PID}"
echo "Conditions: Essential HTN, T2DM, Atrial fibrillation, OA hip, GERD, CKD stage 2"
echo "Allergies: Penicillin, Sulfonamide"
echo "Active medications: 8 (Warfarin, Clopidogrel, Ibuprofen, Metformin, Lisinopril, Amlodipine, Atorvastatin, Omeprazole)"
echo "Task: Pre-operative clearance for elective right total hip arthroplasty"
