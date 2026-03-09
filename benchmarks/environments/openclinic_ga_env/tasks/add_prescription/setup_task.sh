#!/bin/bash
echo "=== Setting up Add Prescription task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# Patient: Carlos Mendoza (personid=10002), seeded in ocadmin_dbo
PATIENT_ID=10002
PATIENT_NAME="CARLOS MENDOZA"
echo "Task patient: $PATIENT_NAME (ID: $PATIENT_ID)"

# Verify patient exists
CARLOS_EXISTS=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PATIENT_ID" | tr -d '[:space:]')
if [ "$CARLOS_EXISTS" = "0" ] || [ -z "$CARLOS_EXISTS" ]; then
    echo "Patient Carlos Mendoza not found — re-running seed..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

echo "$PATIENT_ID" > /tmp/rx_task_patient_id

# Ensure Carlos has a health record
HR_ID=$(clinical_query "SELECT healthRecordId FROM healthrecord WHERE personId=$PATIENT_ID ORDER BY dateBegin DESC LIMIT 1" | head -1 | tr -d '[:space:]')
if [ -z "$HR_ID" ]; then
    clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid)
    VALUES ($PATIENT_ID, '2019-06-10 00:00:00', $PATIENT_ID, 1, 1, 1)" 2>/dev/null || true
    HR_ID=$PATIENT_ID
fi
echo "Health record ID: $HR_ID"

# Ensure Metformin 500mg exists in the products catalog
MET_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_NAME LIKE 'Metformin%'" | tr -d '[:space:]')
if [ "$MET_COUNT" = "0" ] || [ -z "$MET_COUNT" ]; then
    echo "Adding Metformin 500mg to product catalog..."
    clinical_query "INSERT IGNORE INTO oc_products (OC_PRODUCT_SERVERID, OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME, OC_PRODUCT_UNIT, OC_PRODUCT_UNITPRICE, OC_PRODUCT_PACKAGEUNITS, OC_PRODUCT_TOTALUNITS, OC_PRODUCT_CREATETIME, OC_PRODUCT_UPDATETIME, OC_PRODUCT_UPDATEUID, OC_PRODUCT_VERSION)
    VALUES (1, 9002, 'Metformin 500mg', 'tablet', 0.20, 60, 600, NOW(), NOW(), 1, 1)" 2>/dev/null || true
fi
MET_ID=$(clinical_query "SELECT OC_PRODUCT_OBJECTID FROM oc_products WHERE OC_PRODUCT_NAME LIKE 'Metformin%' LIMIT 1" | head -1 | tr -d '[:space:]')
echo "Metformin product ID: $MET_ID"

# Remove any pre-existing Metformin prescriptions for clean state
clinical_query "DELETE FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=$PATIENT_ID AND OC_CHRONICMED_PRODUCTID=$MET_ID" 2>/dev/null || true

# Record baseline counts
INITIAL_RX=$(clinical_query "SELECT COUNT(*) FROM oc_prescriptions" | tr -d '[:space:]' || echo "0")
INITIAL_CHRONICRX=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications" | tr -d '[:space:]' || echo "0")
echo "$INITIAL_RX" > /tmp/initial_prescription_count
echo "$INITIAL_CHRONICRX" > /tmp/initial_chronic_rx_count
echo "Baseline prescriptions: $INITIAL_RX, Chronic meds: $INITIAL_CHRONICRX"

# Launch Firefox at OpenClinic
ensure_openclinic_browser "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Add Prescription task ready ==="
echo "Patient: $PATIENT_NAME (ID=$PATIENT_ID)"
echo "Drug: Metformin 500mg (product ID=$MET_ID)"
echo "Dose: 1 tablet twice daily (2 units/day)"
echo "Start: today"
echo "Login: username=4, password=openclinic"
