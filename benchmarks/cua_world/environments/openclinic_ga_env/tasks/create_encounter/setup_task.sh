#!/bin/bash
echo "=== Setting up Create Encounter task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# Patient: David Okonkwo (personid=10004), seeded in ocadmin_dbo
PATIENT_ID=10004
PATIENT_NAME="DAVID OKONKWO"
echo "Task patient: $PATIENT_NAME (ID: $PATIENT_ID)"

# Verify patient exists
DAVID_EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
if [ "$DAVID_EXISTS" = "0" ] || [ -z "$DAVID_EXISTS" ]; then
    echo "Patient David Okonkwo not found — re-running seed..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

echo "$PATIENT_ID" > /tmp/enc_task_patient_id

# Ensure David has a health record
HR_ID=$(clinical_query "SELECT healthRecordId FROM healthrecord WHERE personId=$PATIENT_ID ORDER BY dateBegin DESC LIMIT 1" | head -1 | tr -d '[:space:]')
if [ -z "$HR_ID" ]; then
    clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid)
    VALUES ($PATIENT_ID, '2018-11-08 00:00:00', $PATIENT_ID, 1, 1, 1)" 2>/dev/null || true
    HR_ID=$PATIENT_ID
fi
echo "Health record ID: $HR_ID"

# Verify ICD-10 J06.9 exists (confirmed present in default install)
ICD_EXISTS=$(clinical_query "SELECT COUNT(*) FROM icd10 WHERE code='J06.9'" | tr -d '[:space:]')
echo "ICD-10 J06.9 in catalog: $ICD_EXISTS entries"

# Record baseline encounter count
INITIAL_ENC=$(clinical_query "SELECT COUNT(*) FROM oc_encounters" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_ENC" > /tmp/initial_encounter_count
echo "Baseline encounter count: $INITIAL_ENC"

# Launch Firefox at OpenClinic
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Create Encounter task ready ==="
echo "Patient: $PATIENT_NAME (ID=$PATIENT_ID)"
echo "Encounter type: Outpatient"
echo "ICD-10: J06.9 (Acute upper respiratory infection, unspecified)"
echo "Login: username=4, password=openclinic"
