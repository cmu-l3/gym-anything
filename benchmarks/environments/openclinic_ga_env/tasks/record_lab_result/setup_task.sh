#!/bin/bash
echo "=== Setting up Record Lab Result task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# Patient: Ana Ferreira (personid=10001), seeded in ocadmin_dbo by seed_data.sql
PATIENT_ID=10001
PATIENT_NAME="ANA FERREIRA"
echo "Task patient: $PATIENT_NAME (ID: $PATIENT_ID)"

# Verify patient exists
ANA_EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
if [ "$ANA_EXISTS" = "0" ] || [ -z "$ANA_EXISTS" ]; then
    echo "ERROR: Patient Ana Ferreira (ID=$PATIENT_ID) not found — re-running seed..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

echo "$PATIENT_ID" > /tmp/lab_task_patient_id

# Ensure GLUC lab analysis exists (labcodeother is varchar(1) — single char only)
LAB_COUNT=$(clinical_query "SELECT COUNT(*) FROM labanalysis WHERE labcode='GLUC'" | tr -d '[:space:]')
if [ "$LAB_COUNT" = "0" ] || [ -z "$LAB_COUNT" ]; then
    echo "Inserting GLUC lab test into catalog..."
    clinical_query "INSERT IGNORE INTO labanalysis (labcode, labtype, labcodeother, unavailable, limitedvisibility, labgroup, monster, biomonitoring, updateuserid, updatetime, unit, historydays, historyvalues, section)
    VALUES ('GLUC', 'CHEM', 'G', 0, 0, 'CHEMISTRY', 'blood', 0, 1, NOW(), 'mg/dL', 365, 20, 'Chemistry')" 2>/dev/null || true
fi

# Ensure Ana Ferreira has a health record
HR_ID=$(clinical_query "SELECT healthRecordId FROM healthrecord WHERE personId=$PATIENT_ID ORDER BY dateBegin DESC LIMIT 1" | head -1 | tr -d '[:space:]')
if [ -z "$HR_ID" ]; then
    echo "Creating health record for Ana Ferreira..."
    clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid)
    VALUES ($PATIENT_ID, '2020-01-15 00:00:00', $PATIENT_ID, 1, 1, 1)" 2>/dev/null || true
    HR_ID=$PATIENT_ID
fi
echo "Health record ID: $HR_ID"

# Remove any previously inserted pending GLUC requests for this patient (clean state)
clinical_query "DELETE FROM requestedlabanalyses WHERE patientid=$PATIENT_ID AND analysiscode='GLUC' AND resultvalue IS NULL" 2>/dev/null || true

# Create a fresh pending GLUC lab request
MAX_TXN=$(clinical_query "SELECT COALESCE(MAX(transactionId),10000)+1 FROM transactions" | head -1 | tr -d '[:space:]')
MAX_TXN=${MAX_TXN:-10001}

clinical_query "INSERT INTO transactions (transactionId, creationDate, transactionType, updateTime, status, healthRecordId, userId, serverid, version, versionserverid)
VALUES ($MAX_TXN, NOW(), 'Lab', NOW(), 0, $HR_ID, 1, 1, 1, 1)" 2>/dev/null || echo "Transaction insert warning (continuing)"

clinical_query "INSERT INTO requestedlabanalyses (transactionid, analysiscode, patientid, requestdatetime, samplereceptiondatetime, sampletakendatetime, serverid, comment)
VALUES ($MAX_TXN, 'GLUC', $PATIENT_ID, NOW(), NOW(), NOW(), 1, 'Fasting blood glucose screening')" 2>/dev/null || echo "Lab request insert warning (continuing)"

PENDING=$(clinical_query "SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=$PATIENT_ID AND analysiscode='GLUC' AND resultvalue IS NULL" | tr -d '[:space:]')
echo "Pending GLUC requests for Ana Ferreira: $PENDING"

# Baseline count of completed results
INITIAL_RESULTS=$(clinical_query "SELECT COUNT(*) FROM requestedlabanalyses WHERE resultvalue IS NOT NULL" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_RESULTS" > /tmp/initial_lab_count

# Launch Firefox at OpenClinic
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Record Lab Result task ready ==="
echo "Patient: $PATIENT_NAME (ID=$PATIENT_ID)"
echo "Pending lab test: GLUC (Blood Glucose) — enter result 145 mg/dL"
echo "Login: username=4, password=openclinic"
