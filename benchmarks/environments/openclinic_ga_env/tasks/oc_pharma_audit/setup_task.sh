#!/bin/bash
# setup_task.sh — oc_pharma_audit: Pharmacy Medication Safety Audit
# Injects three deliberate medication errors for agents to discover and correct.
# A fourth patient (Li Wei) has a correct chronic medication (decoy — must NOT be removed).

set -euo pipefail
echo "=== Setting up Pharmacy Medication Safety Audit task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# ---------------------------------------------------------------
# Verify required patients exist; re-seed if missing
# ---------------------------------------------------------------
for PID in 10003 10007 10008 10009; do
    COUNT=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PID" | tr -d '[:space:]')
    if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
        echo "Patient $PID missing — re-seeding..."
        /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
        break
    fi
done

# ---------------------------------------------------------------
# Ensure each patient has a health record
# ---------------------------------------------------------------
for PID in 10003 10007 10008 10009; do
    HR=$(clinical_query "SELECT COUNT(*) FROM healthrecord WHERE personId=$PID" | tr -d '[:space:]')
    if [ "$HR" = "0" ] || [ -z "$HR" ]; then
        clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid) VALUES ($PID, NOW(), $PID, 1, 1, 1)" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------
# Ensure all required medications exist in product catalog
# Product IDs: 9001=Amoxicillin, 9002=Metformin, 9004=Amlodipine, 9005=Atorvastatin
# ---------------------------------------------------------------
for OID in 9001 9002 9004 9005; do
    CNT=$(clinical_query "SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_OBJECTID=$OID" | tr -d '[:space:]')
    if [ "$CNT" = "0" ] || [ -z "$CNT" ]; then
        echo "Re-seeding product $OID..."
        /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
        break
    fi
done

# ---------------------------------------------------------------
# Clean slate: remove any prior chronic meds for these patients
# ---------------------------------------------------------------
echo "Clearing prior chronic medication state for audit patients..."
clinical_query "DELETE FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID IN (10003, 10007, 10008, 10009)" 2>/dev/null || true

# ---------------------------------------------------------------
# Discover oc_chronicmedications schema and insert errors safely
# ---------------------------------------------------------------
python3 << 'PYEOF'
import subprocess
import sys

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

# Discover columns in oc_chronicmedications
col_info = q("SHOW COLUMNS FROM oc_chronicmedications")
cols = [line.split('\t')[0] for line in col_info.splitlines() if line.strip()]
print(f"Columns: {cols}", file=sys.stderr)

def insert_chronic_med(patient_id, product_id, obj_id, posology):
    """Insert a chronic medication entry using available columns."""
    # Build INSERT using only columns we know exist
    col_map = {
        'OC_CHRONICMED_PATIENTID': patient_id,
        'OC_CHRONICMED_PRODUCTID': product_id,
    }
    # Optional columns — add if they exist
    if 'OC_CHRONICMED_OBJECTID' in cols:
        col_map['OC_CHRONICMED_OBJECTID'] = obj_id
    if 'OC_CHRONICMED_SERVERID' in cols:
        col_map['OC_CHRONICMED_SERVERID'] = 1
    if 'OC_CHRONICMED_POSOLOGY' in cols:
        col_map['OC_CHRONICMED_POSOLOGY'] = f"'{posology}'"
    if 'OC_CHRONICMED_STARTDATE' in cols:
        col_map['OC_CHRONICMED_STARTDATE'] = 'NOW()'
    if 'OC_CHRONICMED_UPDATETIME' in cols:
        col_map['OC_CHRONICMED_UPDATETIME'] = 'NOW()'
    if 'OC_CHRONICMED_UPDATEUSERID' in cols:
        col_map['OC_CHRONICMED_UPDATEUSERID'] = 1
    if 'OC_CHRONICMED_VERSION' in cols:
        col_map['OC_CHRONICMED_VERSION'] = 1
    if 'OC_CHRONICMED_VERSIONSERVERID' in cols:
        col_map['OC_CHRONICMED_VERSIONSERVERID'] = 1

    col_names = ', '.join(col_map.keys())
    col_vals = ', '.join(str(v) for v in col_map.values())
    sql = f"INSERT IGNORE INTO oc_chronicmedications ({col_names}) VALUES ({col_vals})"
    result = q(sql)
    return result

# ERROR 1: Fatima Al-Rashid (10003) — Amoxicillin 500mg (9001) listed as chronic med
# Clinical error: antibiotics are short-course acute medications; listing as chronic is unsafe
print("Injecting ERROR 1: Amoxicillin as chronic med for Fatima (10003)...", file=sys.stderr)
insert_chronic_med(10003, 9001, 80001, '1 capsule three times daily for infection')

# ERROR 2: Priya Sharma (10007) — Amlodipine 5mg (9004) listed TWICE (duplicate)
# Clinical error: duplicate prescription creates overdose risk
print("Injecting ERROR 2: Duplicate Amlodipine for Priya (10007)...", file=sys.stderr)
insert_chronic_med(10007, 9004, 80002, '1 tablet once daily')
insert_chronic_med(10007, 9004, 80003, '1 tablet once daily — copy')

# ERROR 3: Mohammed Hassan (10008) — Metformin 500mg (9002) listed as chronic med
# Clinical error: Metformin is contraindicated in renal failure (his CREAT=4.5 is critical)
print("Injecting ERROR 3: Metformin for Mohammed (10008) with high CREAT...", file=sys.stderr)
insert_chronic_med(10008, 9002, 80004, '1 tablet twice daily')

# CORRECT (decoy): Li Wei (10009) — Atorvastatin 20mg (9005) as chronic med
# This is clinically appropriate — must NOT be removed
print("Injecting CORRECT decoy: Atorvastatin for Li Wei (10009)...", file=sys.stderr)
insert_chronic_med(10009, 9005, 80005, '1 tablet once daily at bedtime')

# Verify insertions
for pid, label in [(10003, 'Fatima'), (10007, 'Priya'), (10008, 'Mohammed'), (10009, 'Li Wei')]:
    cnt = q(f"SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID={pid}")
    print(f"  {label} ({pid}): {cnt} chronic med(s)", file=sys.stderr)

print("Chronic med injection complete.", file=sys.stderr)
PYEOF

echo "Chronic medication errors injected."

# ---------------------------------------------------------------
# ERROR 3 support: inject critical CREAT lab result for Mohammed (10008)
# This is the laboratory evidence for the Metformin contraindication
# CREAT=4.5 mg/dL is severely elevated (normal <1.2) → Stage 4-5 CKD
# ---------------------------------------------------------------
echo "Injecting critical CREAT lab result for Mohammed Hassan (10008)..."

python3 << 'PYEOF'
import subprocess
import sys

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

# Discover columns in requestedlabanalyses
col_info = q("SHOW COLUMNS FROM requestedlabanalyses")
cols = [line.split('\t')[0] for line in col_info.splitlines() if line.strip()]
print(f"requestedlabanalyses columns: {cols}", file=sys.stderr)

# Delete any prior CREAT for Mohammed to start clean
q("DELETE FROM requestedlabanalyses WHERE patientid=10008 AND analysiscode='CREAT'")

# Build INSERT for the critical CREAT result
col_map = {
    'patientid': 10008,
    'analysiscode': "'CREAT'",
    'requestdatetime': 'NOW()',
}
if 'transactionid' in cols:
    col_map['transactionid'] = 80100
if 'samplereceptiondatetime' in cols:
    col_map['samplereceptiondatetime'] = 'NOW()'
if 'sampletakendatetime' in cols:
    col_map['sampletakendatetime'] = 'NOW()'
if 'serverid' in cols:
    col_map['serverid'] = 1
if 'resultvalue' in cols:
    col_map['resultvalue'] = "'4.5'"  # Critical CREAT: severe renal failure
if 'comment' in cols:
    col_map['comment'] = "'CRITICAL: Severe renal impairment. GFR estimated <15 mL/min.'"

col_names = ', '.join(col_map.keys())
col_vals = ', '.join(str(v) for v in col_map.values())
sql = f"INSERT INTO requestedlabanalyses ({col_names}) VALUES ({col_vals})"
r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
if r.returncode != 0:
    print(f"CREAT insert stderr: {r.stderr}", file=sys.stderr)
else:
    print("Critical CREAT result inserted for Mohammed (10008): 4.5 mg/dL", file=sys.stderr)
PYEOF

# ---------------------------------------------------------------
# Record baseline state for verifier anti-gaming
# ---------------------------------------------------------------
FATIMA_MED=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10003 AND OC_CHRONICMED_PRODUCTID=9001" | tr -d '[:space:]')
PRIYA_DUP=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10007 AND OC_CHRONICMED_PRODUCTID=9004" | tr -d '[:space:]')
MOHAM_MET=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10008 AND OC_CHRONICMED_PRODUCTID=9002" | tr -d '[:space:]')
LIWEI_STA=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID=10009 AND OC_CHRONICMED_PRODUCTID=9005" | tr -d '[:space:]')

echo "Baseline state recorded:"
echo "  Fatima Amoxicillin entries: $FATIMA_MED (should be 1)"
echo "  Priya Amlodipine entries: $PRIYA_DUP (should be 2)"
echo "  Mohammed Metformin entries: $MOHAM_MED (should be 1)"
echo "  Li Wei Atorvastatin entries: $LIWEI_STA (should be 1)"

# ---------------------------------------------------------------
# Launch browser at OpenClinic
# ---------------------------------------------------------------
ensure_openclinic_browser "http://localhost:10088/openclinic"
navigate_to_url "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Pharmacy Medication Safety Audit task ready ==="
echo ""
echo "TASK: Review chronic medication lists for 4 patients and fix safety issues."
echo "Patients: Fatima Al-Rashid (10003), Priya Sharma (10007),"
echo "          Mohammed Hassan (10008), Li Wei (10009)"
echo "Login: username=4, password=openclinic"
echo "URL: http://localhost:10088/openclinic"
