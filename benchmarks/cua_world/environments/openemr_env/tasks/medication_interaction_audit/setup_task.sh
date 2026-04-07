#!/bin/bash
# Note: no set -euo pipefail — DB pipeline commands need to be fault-tolerant

source /workspace/scripts/task_utils.sh

PATIENT_FNAME="James"
PATIENT_LNAME="Kowalski"
PATIENT_DOB="1968-04-15"

# --- Record task start timestamp (anti-gaming) ---
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# --- Clean state from prior runs ---
rm -f /tmp/medication_audit_result.json /tmp/initial_rx_ids.txt
echo "" > /tmp/task_patient_pid

# --- Check / create patient ---
PATIENT_PID=$(openemr_query "SELECT pid FROM patient_data WHERE fname='${PATIENT_FNAME}' AND lname='${PATIENT_LNAME}' AND DOB='${PATIENT_DOB}' LIMIT 1;" 2>/dev/null | tr -d ' \t\n\r' || echo "")

if [ -z "$PATIENT_PID" ] || ! echo "$PATIENT_PID" | grep -qE '^[0-9]+$'; then
    echo "Creating patient ${PATIENT_FNAME} ${PATIENT_LNAME}..."
    MAX_PID=$(openemr_query "SELECT COALESCE(MAX(pid),0) FROM patient_data;" 2>/dev/null | tr -d ' \t\n\r' || echo "100")
    NEW_PID=$((MAX_PID + 1))
    openemr_query "INSERT INTO patient_data (pid, pubpid, fname, lname, DOB, sex, ss, street, city, state, postal_code, phone_home, provider_id, date, regdate)
        VALUES (${NEW_PID}, 'PT-$(printf '%05d' ${NEW_PID})', '${PATIENT_FNAME}', '${PATIENT_LNAME}', '${PATIENT_DOB}', 'Male', '987-65-4321',
                '145 Maple Street', 'Burlington', 'VT', '05401', '802-555-4321', 1, NOW(), NOW());"
    PATIENT_PID="$NEW_PID"
    echo "Created patient PID: ${PATIENT_PID}"
else
    echo "Patient exists with PID: ${PATIENT_PID}"
    # Clean up any existing medications from prior runs
    openemr_query "UPDATE prescriptions SET active=0 WHERE patient_id=${PATIENT_PID};" 2>/dev/null || true
fi

echo "$PATIENT_PID" > /tmp/task_patient_pid

# --- Ensure prescriber user exists (use user id 1 = admin) ---
PRESCRIBER_ID=1

# --- Add 6 medications ---
# Note: `interval` is a MySQL reserved keyword.
# Use chr(96) in Python to construct backtick-quoted column name safely,
# avoiding any bash command-substitution interpretation of backtick characters.
openemr_query "DELETE FROM prescriptions WHERE patient_id=${PATIENT_PID} AND drug IN ('Amlodipine','Atorvastatin','Lisinopril','Metformin','Ibuprofen','Nitrofurantoin');" 2>/dev/null || true

python3 << PYEOF
import subprocess, sys

pid = ${PATIENT_PID}
prescriber = ${PRESCRIBER_ID}

meds = [
    ("Amlodipine 5 MG Oral Tablet",        "Hypertension - calcium channel blocker, safe in CKD", 1),
    ("Atorvastatin 20 MG Oral Tablet",      "Hyperlipidemia - LDL reduction, safe in CKD",         1),
    ("Lisinopril 5 MG Oral Tablet",         "Hypertension and renoprotection in CKD",               1),
    ("Metformin 500 MG Oral Tablet",        "Type 2 diabetes management",                          1),
    ("Ibuprofen 400 MG Oral Tablet",        "PRN pain management - NSAID",                         1),
    ("Nitrofurantoin 100 MG Oral Capsule",  "UTI prophylaxis",                                     1),
]

# NOT NULL columns in prescriptions: txDate (date), usage_category_title, request_intent_title
cols = ("patient_id, date_added, provider_id, drug, refills, note, active, "
        "txDate, usage_category_title, request_intent_title")

inserted = 0
for drug, note, active in meds:
    sql = ("INSERT INTO prescriptions (" + cols + ") VALUES ("
           + str(pid) + ", NOW(), " + str(prescriber) + ", "
           + "'" + drug + "', 5, '" + note + "', " + str(active) + ", CURDATE(), '', '');")
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

print("Inserted " + str(inserted) + "/6 medications for PID " + str(pid))
sys.exit(0 if inserted == 6 else 1)
PYEOF
RX_INSERT_EXIT=$?
[ $RX_INSERT_EXIT -eq 0 ] && echo "All 6 medications inserted OK" || echo "WARN: Some medication inserts may have failed (exit $RX_INSERT_EXIT)"

echo "Added 6 medications for patient PID ${PATIENT_PID}"

# --- Record initial state for delta detection ---
INITIAL_RX_COUNT=$(openemr_query "SELECT COUNT(*) FROM prescriptions WHERE patient_id=${PATIENT_PID} AND active=1;" 2>/dev/null | tr -d ' \t\n\r' || echo "6")
echo "${INITIAL_RX_COUNT:-6}" > /tmp/initial_rx_count

INITIAL_LAB_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_order WHERE patient_id=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
echo "${INITIAL_LAB_COUNT:-0}" > /tmp/initial_lab_count

INITIAL_NOTE_COUNT=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=${PATIENT_PID};" 2>/dev/null | tr -d ' \t\n\r' || echo "0")
echo "${INITIAL_NOTE_COUNT:-0}" > /tmp/initial_note_count

echo "Baseline: rx=${INITIAL_RX_COUNT} labs=${INITIAL_LAB_COUNT} notes=${INITIAL_NOTE_COUNT}"

# --- Launch Firefox with OpenEMR ---
# Correct URL: no /openemr prefix — served directly at http://localhost/
OPENEMR_LOGIN_URL="http://localhost/interface/login/login.php?site=default"

# Kill any running Firefox first to avoid "already running" conflict dialogs
pkill -u ga -f firefox 2>/dev/null || true
sleep 3

# Wait for OpenEMR to respond (max 60s)
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

take_screenshot "/tmp/medication_audit_start.png" || true

echo "=== Setup complete ==="
echo "Patient: ${PATIENT_FNAME} ${PATIENT_LNAME} (DOB: ${PATIENT_DOB}) | PID: ${PATIENT_PID}"
echo "Active medications: ${INITIAL_RX_COUNT} (3 safe, 3 contraindicated for CKD3b)"
echo "Task: Review medications for CKD stage 3b (eGFR 38 mL/min/1.73m²)"
