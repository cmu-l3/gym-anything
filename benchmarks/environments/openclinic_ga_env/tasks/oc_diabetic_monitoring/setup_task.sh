#!/bin/bash
# setup_task.sh — oc_diabetic_monitoring: Diabetes HbA1c Compliance Audit
#
# Seeds the following scenario:
#   - Ana Ferreira (10001):   High GLUC (156 mg/dL), NO HbA1c → NEEDS HbA1c
#   - Maria Santos (10005):   High GLUC (189 mg/dL), HbA1c >90 days ago (stale) → NEEDS HbA1c
#   - Priya Sharma (10007):   High GLUC (142 mg/dL), NO HbA1c → NEEDS HbA1c
#   - Elena Popescu (10010):  High GLUC (135 mg/dL), current HbA1c 45 days ago → NO test needed (decoy)
#
# All 4 patients have elevated GLUC. The agent must determine from the HbA1c
# history which patients need a new order (3) versus which already have current
# monitoring (1). This requires reading lab history, not just GLUC values.

set -euo pipefail
echo "=== Setting up Diabetes HbA1c Compliance Audit task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# ---------------------------------------------------------------
# Verify patients exist
# ---------------------------------------------------------------
for PID in 10001 10005 10007 10010; do
    COUNT=$(admin_query "SELECT COUNT(*) FROM adminview WHERE personid=$PID" | tr -d '[:space:]')
    if [ "$COUNT" = "0" ] || [ -z "$COUNT" ]; then
        echo "Patient $PID missing — re-seeding..."
        /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
        break
    fi
done

# Ensure health records exist
for PID in 10001 10005 10007 10010; do
    HR=$(clinical_query "SELECT COUNT(*) FROM healthrecord WHERE personId=$PID" | tr -d '[:space:]')
    if [ "$HR" = "0" ] || [ -z "$HR" ]; then
        clinical_query "INSERT IGNORE INTO healthrecord (healthRecordId, dateBegin, personId, serverid, version, versionserverid) VALUES ($PID, NOW(), $PID, 1, 1, 1)" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------
# Ensure GLUC and HBA1C lab analysis codes exist
# ---------------------------------------------------------------
GLUC_COUNT=$(clinical_query "SELECT COUNT(*) FROM labanalysis WHERE labcode='GLUC'" | tr -d '[:space:]')
if [ "$GLUC_COUNT" = "0" ]; then
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Clean slate: remove prior GLUC/HBA1C lab results for these patients
# ---------------------------------------------------------------
echo "Clearing prior lab results for audit patients..."
clinical_query "DELETE FROM requestedlabanalyses WHERE patientid IN (10001, 10005, 10007, 10010) AND analysiscode IN ('GLUC', 'HBA1C')" 2>/dev/null || true

# ---------------------------------------------------------------
# Inject scenario using Python for schema-safe INSERTs
# ---------------------------------------------------------------
python3 << 'PYEOF'
import subprocess
import sys
from datetime import datetime, timedelta

MYSQL = ['/opt/openclinic/mysql5/bin/mysql', '-S', '/tmp/mysql5.sock', '-u', 'root', 'openclinic_dbo', '-N', '-e']

def q(sql):
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    return r.stdout.strip()

# Discover requestedlabanalyses columns
col_info = q("SHOW COLUMNS FROM requestedlabanalyses")
cols = [line.split('\t')[0] for line in col_info.splitlines() if line.strip()]
print(f"requestedlabanalyses columns: {cols}", file=sys.stderr)

now = datetime.now()
days_ago_100 = (now - timedelta(days=100)).strftime('%Y-%m-%d %H:%M:%S')
days_ago_45 = (now - timedelta(days=45)).strftime('%Y-%m-%d %H:%M:%S')

def insert_lab(tx_id, patient_id, code, result_val, taken_dt, comment=''):
    col_map = {
        'patientid': patient_id,
        'analysiscode': f"'{code}'",
        'requestdatetime': f"'{taken_dt}'",
    }
    if 'transactionid' in cols:
        col_map['transactionid'] = tx_id
    if 'samplereceptiondatetime' in cols:
        col_map['samplereceptiondatetime'] = f"'{taken_dt}'"
    if 'sampletakendatetime' in cols:
        col_map['sampletakendatetime'] = f"'{taken_dt}'"
    if 'serverid' in cols:
        col_map['serverid'] = 1
    if 'resultvalue' in cols:
        col_map['resultvalue'] = f"'{result_val}'"
    if 'comment' in cols:
        col_map['comment'] = f"'{comment}'"

    col_names = ', '.join(col_map.keys())
    col_vals = ', '.join(str(v) for v in col_map.values())
    sql = f"INSERT INTO requestedlabanalyses ({col_names}) VALUES ({col_vals})"
    r = subprocess.run(MYSQL + [sql], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  INSERT failed: {r.stderr.strip()}", file=sys.stderr)

today = now.strftime('%Y-%m-%d %H:%M:%S')

# Ana Ferreira (10001): High GLUC, NO HbA1c → NEEDS HbA1c
print("Seeding Ana Ferreira (10001): GLUC=156 mg/dL, no HbA1c...", file=sys.stderr)
insert_lab(81001, 10001, 'GLUC', '156', today, 'Fasting glucose - elevated')

# Maria Santos (10005): High GLUC, HbA1c >90 days ago → NEEDS HbA1c (stale)
print("Seeding Maria Santos (10005): GLUC=189 mg/dL, HbA1c 100 days ago...", file=sys.stderr)
insert_lab(81002, 10005, 'GLUC', '189', today, 'Fasting glucose - elevated')
insert_lab(81003, 10005, 'HBA1C', '7.2', days_ago_100, 'HbA1c - outdated result')

# Priya Sharma (10007): High GLUC, NO HbA1c → NEEDS HbA1c
print("Seeding Priya Sharma (10007): GLUC=142 mg/dL, no HbA1c...", file=sys.stderr)
insert_lab(81004, 10007, 'GLUC', '142', today, 'Fasting glucose - elevated')

# Elena Popescu (10010): High GLUC, recent HbA1c (45 days ago) → NO new test needed
print("Seeding Elena Popescu (10010): GLUC=135 mg/dL, HbA1c 45 days ago (current)...", file=sys.stderr)
insert_lab(81005, 10010, 'GLUC', '135', today, 'Fasting glucose - elevated')
insert_lab(81006, 10010, 'HBA1C', '6.8', days_ago_45, 'HbA1c - current result within 90 days')

print("Lab scenario seeded.", file=sys.stderr)
PYEOF

echo "Lab results injected."

# ---------------------------------------------------------------
# Record timestamps for post-task HbA1c order verification
# ---------------------------------------------------------------
START_TS=$(date +%s)
echo "$START_TS" > /tmp/diabetic_task_start_ts
echo "Task start timestamp: $START_TS"

# ---------------------------------------------------------------
# Record baseline HBA1C order counts for each patient
# ---------------------------------------------------------------
for PID in 10001 10005 10007 10010; do
    CNT=$(clinical_query "SELECT COUNT(*) FROM requestedlabanalyses WHERE patientid=$PID AND analysiscode='HBA1C'" | tr -d '[:space:]')
    echo "  Patient $PID baseline HBA1C orders: $CNT"
done

# ---------------------------------------------------------------
# Launch browser
# ---------------------------------------------------------------
ensure_openclinic_browser "http://localhost:10088/openclinic"
navigate_to_url "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Diabetes HbA1c Compliance Audit task ready ==="
echo ""
echo "TASK: Order HbA1c for patients requiring it per protocol:"
echo "  - Ana Ferreira (10001):  GLUC=156, no HbA1c     → ORDER HbA1c"
echo "  - Maria Santos (10005):  GLUC=189, HbA1c 100d    → ORDER HbA1c (stale)"
echo "  - Priya Sharma (10007):  GLUC=142, no HbA1c     → ORDER HbA1c"
echo "  - Elena Popescu (10010): GLUC=135, HbA1c 45d     → NO order (current)"
echo "Login: username=4, password=openclinic"
