#!/bin/bash
# setup_task.sh — oc_critical_lab_followup: Critical Lab Value Response Protocol
#
# Seeds critical lab values for 3 patients, plus 1 normal patient (decoy):
#
#   Fatima Al-Rashid (10003): Critical GLUC = 450 mg/dL (critical hyperglycemia)
#     → Agent must: schedule urgent appt + add medication response
#     → Note: Insulin Regular must be added to the product catalog first
#
#   David Okonkwo (10004): Critical CBC = 6.1 g/dL hemoglobin (critical anemia)
#     → Agent must: schedule urgent appt + add Folic Acid 5mg
#
#   Li Wei (10009): Critical CREAT = 4.8 mg/dL (severe renal failure)
#     → Agent must: schedule urgent appt + ensure Metformin removed
#     → Li Wei's Metformin is pre-loaded into chronic meds as a trap
#
#   David Okonkwo (10004) also has Metformin (but NOT critical CREAT) — decoy
#     → Metformin is appropriate for David (normal CREAT) — should not be removed

set -euo pipefail
echo "=== Setting up Critical Lab Value Response Protocol task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# ---------------------------------------------------------------
# Ensure required patients exist
# ---------------------------------------------------------------
for PID in 10003 10004 10009; do
    COUNT=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PID" | tr -d '[:space:]')
    if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
        echo "Patient $PID missing — re-seeding..."
        /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
        break
    fi
done

# Ensure health records exist
for PID in 10003 10004 10009; do
    HR=$(clinical_query "SELECT COUNT(*) FROM healthrecord WHERE personId=$PID" | tr -d '[:space:]')
    if [ "$HR" = "0" ] || [ -z "$HR" ]; then
        clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid) VALUES ($PID, NOW(), $PID, 1, 1, 1)" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------
# Ensure lab codes exist
# ---------------------------------------------------------------
LAB_COUNT=$(clinical_query "SELECT COUNT(*) FROM labanalysis WHERE labcode IN ('GLUC', 'CBC', 'CREAT')" | tr -d '[:space:]')
if [ "$LAB_COUNT" -lt 3 ]; then
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Ensure Metformin (9002) exists in product catalog
# ---------------------------------------------------------------
MET_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_OBJECTID=9002" | tr -d '[:space:]')
if [ "$MET_COUNT" = "0" ]; then
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Add Folic Acid 5mg and Insulin Regular to product catalog
# (these are required for the medication responses)
# ---------------------------------------------------------------
python3 << 'PYEOF'
import subprocess, sys

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

# Add Folic Acid 5mg (OID=9011)
folic = q("SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_OBJECTID=9011")
if folic == '0' or not folic:
    q("INSERT IGNORE INTO oc_products (OC_PRODUCT_SERVERID, OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME, OC_PRODUCT_UNIT, OC_PRODUCT_UNITPRICE, OC_PRODUCT_PACKAGEUNITS, OC_PRODUCT_TOTALUNITS, OC_PRODUCT_CREATETIME, OC_PRODUCT_UPDATETIME, OC_PRODUCT_UPDATEUID, OC_PRODUCT_VERSION) VALUES (1, 9011, 'Folic Acid 5mg', 'tablet', 0.05, 100, 1000, NOW(), NOW(), 1, 1)")
    print("Added Folic Acid 5mg (9011)", file=sys.stderr)

# Add Insulin Regular 100IU/mL (OID=9012)
insulin = q("SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_OBJECTID=9012")
if insulin == '0' or not insulin:
    q("INSERT IGNORE INTO oc_products (OC_PRODUCT_SERVERID, OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME, OC_PRODUCT_UNIT, OC_PRODUCT_UNITPRICE, OC_PRODUCT_PACKAGEUNITS, OC_PRODUCT_TOTALUNITS, OC_PRODUCT_CREATETIME, OC_PRODUCT_UPDATETIME, OC_PRODUCT_UPDATEUID, OC_PRODUCT_VERSION) VALUES (1, 9012, 'Insulin Regular 100IU/mL', 'vial', 5.00, 10, 100, NOW(), NOW(), 1, 1)")
    print("Added Insulin Regular 100IU/mL (9012)", file=sys.stderr)

print("Product catalog updated.", file=sys.stderr)
PYEOF

# ---------------------------------------------------------------
# Clean up prior lab results and medications for these patients
# ---------------------------------------------------------------
echo "Clearing prior state for critical lab patients..."
clinical_query "DELETE FROM requestedlabanalyses WHERE patientid IN (10003, 10004, 10009)" 2>/dev/null || true
clinical_query "DELETE FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID IN (10003, 10004, 10009)" 2>/dev/null || true
clinical_query "DELETE FROM oc_planning WHERE OC_PLANNING_PATIENTID IN (10003, 10004, 10009)" 2>/dev/null || true

# ---------------------------------------------------------------
# Inject critical lab values and pre-existing medication traps
# ---------------------------------------------------------------
python3 << 'PYEOF'
import subprocess, sys

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  SQL error: {r.stderr.strip()}", file=sys.stderr)
    return r.stdout.strip()

# Get column names for requestedlabanalyses
col_info = q("SHOW COLUMNS FROM requestedlabanalyses")
lab_cols = [line.split('\t')[0] for line in col_info.splitlines() if line.strip()]

col_info2 = q("SHOW COLUMNS FROM oc_chronicmedications")
med_cols = [line.split('\t')[0] for line in col_info2.splitlines() if line.strip()]

print(f"Lab cols: {lab_cols}", file=sys.stderr)
print(f"Med cols: {med_cols}", file=sys.stderr)

def insert_lab(tx_id, patient_id, code, result_val, comment='CRITICAL'):
    col_map = {
        'patientid': patient_id,
        'analysiscode': f"'{code}'",
        'requestdatetime': 'NOW()',
    }
    if 'transactionid' in lab_cols:
        col_map['transactionid'] = tx_id
    if 'samplereceptiondatetime' in lab_cols:
        col_map['samplereceptiondatetime'] = 'NOW()'
    if 'sampletakendatetime' in lab_cols:
        col_map['sampletakendatetime'] = 'NOW()'
    if 'serverid' in lab_cols:
        col_map['serverid'] = 1
    if 'resultvalue' in lab_cols:
        col_map['resultvalue'] = f"'{result_val}'"
    if 'comment' in lab_cols:
        col_map['comment'] = f"'{comment}'"
    col_names = ', '.join(col_map.keys())
    col_vals = ', '.join(str(v) for v in col_map.values())
    q(f"INSERT INTO requestedlabanalyses ({col_names}) VALUES ({col_vals})")

def insert_chromed(patient_id, product_id, obj_id, posology='1 tablet daily'):
    col_map = {
        'OC_CHRONICMED_PATIENTID': patient_id,
        'OC_CHRONICMED_PRODUCTID': product_id,
    }
    if 'OC_CHRONICMED_OBJECTID' in med_cols:
        col_map['OC_CHRONICMED_OBJECTID'] = obj_id
    if 'OC_CHRONICMED_SERVERID' in med_cols:
        col_map['OC_CHRONICMED_SERVERID'] = 1
    if 'OC_CHRONICMED_POSOLOGY' in med_cols:
        col_map['OC_CHRONICMED_POSOLOGY'] = f"'{posology}'"
    if 'OC_CHRONICMED_STARTDATE' in med_cols:
        col_map['OC_CHRONICMED_STARTDATE'] = 'NOW()'
    if 'OC_CHRONICMED_UPDATETIME' in med_cols:
        col_map['OC_CHRONICMED_UPDATETIME'] = 'NOW()'
    if 'OC_CHRONICMED_UPDATEUSERID' in med_cols:
        col_map['OC_CHRONICMED_UPDATEUSERID'] = 1
    if 'OC_CHRONICMED_VERSION' in med_cols:
        col_map['OC_CHRONICMED_VERSION'] = 1
    col_names = ', '.join(col_map.keys())
    col_vals = ', '.join(str(v) for v in col_map.values())
    q(f"INSERT IGNORE INTO oc_chronicmedications ({col_names}) VALUES ({col_vals})")

# --- Fatima Al-Rashid (10003): Critical GLUC = 450 mg/dL ---
print("Seeding Fatima (10003): Critical GLUC=450...", file=sys.stderr)
insert_lab(82001, 10003, 'GLUC', '450', 'CRITICAL HIGH: Glucose 450 mg/dL (>400). Urgent management required.')

# --- David Okonkwo (10004): Critical CBC = 6.1 g/dL Hgb ---
print("Seeding David (10004): Critical CBC Hgb=6.1...", file=sys.stderr)
insert_lab(82002, 10004, 'CBC', '6.1', 'CRITICAL LOW: Hemoglobin 6.1 g/dL (<7.0). Severe anemia.')
# David also has Metformin as chronic med (this is appropriate since his CREAT is normal)
insert_chromed(10004, 9002, 90010, '1 tablet twice daily')

# --- Li Wei (10009): Critical CREAT = 4.8 mg/dL ---
print("Seeding Li Wei (10009): Critical CREAT=4.8...", file=sys.stderr)
insert_lab(82003, 10009, 'CREAT', '4.8', 'CRITICAL HIGH: Creatinine 4.8 mg/dL (>4.0). Severe CKD.')
# Li Wei has Metformin as chronic med — this must be REMOVED (contraindicated)
insert_chromed(10009, 9002, 90011, '1 tablet twice daily')

print("Critical lab scenario seeded.", file=sys.stderr)
PYEOF

echo "Critical lab values injected."

# ---------------------------------------------------------------
# Record task start time for verifier
# ---------------------------------------------------------------
date +%s > /tmp/critical_lab_start_ts

# ---------------------------------------------------------------
# Launch browser
# ---------------------------------------------------------------
ensure_openclinic_browser "http://localhost:10088/openclinic"
navigate_to_url "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Critical Lab Value Response Protocol task ready ==="
echo ""
echo "Critical values seeded:"
echo "  Fatima Al-Rashid (10003): GLUC=450 mg/dL (critical hyperglycemia)"
echo "  David Okonkwo   (10004): CBC Hgb=6.1 g/dL (critical anemia)"
echo "  Li Wei          (10009): CREAT=4.8 mg/dL (critical renal failure)"
echo ""
echo "Medication traps:"
echo "  David (10004): Metformin on chronic list — SHOULD remain (normal CREAT)"
echo "  Li Wei (10009): Metformin on chronic list — MUST be removed (critical CREAT)"
echo ""
echo "Login: username=4, password=openclinic"
