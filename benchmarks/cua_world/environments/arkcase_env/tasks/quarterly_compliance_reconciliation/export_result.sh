#!/bin/bash
# post_task: Export results for quarterly_compliance_reconciliation
# Uses only PostgreSQL DB queries (no REST API) for reliability.

echo "=== Exporting quarterly_compliance_reconciliation result ==="

# Pre-set ARKCASE_NS before sourcing task_utils.sh
export ARKCASE_NS="arkcase"
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── 1. Load case IDs from setup ──────────────────────────────────────────────
if [ ! -f /tmp/reconciliation_case_ids.json ]; then
    echo "ERROR: Setup IDs file not found"
    echo '{"error": "Setup IDs file not found"}' > /tmp/task_result.json
    chmod 666 /tmp/task_result.json
    exit 0
fi

C1_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case1'])" 2>/dev/null || echo "0")
C2_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case2'])" 2>/dev/null || echo "0")
C3_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case3'])" 2>/dev/null || echo "0")
C4_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case4'])" 2>/dev/null || echo "0")
C5_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case5'])" 2>/dev/null || echo "0")
C6_ID=$(python3 -c "import json; print(json.load(open('/tmp/reconciliation_case_ids.json'))['case6'])" 2>/dev/null || echo "0")

ALL_IDS="${C1_ID},${C2_ID},${C3_ID},${C4_ID},${C5_ID},${C6_ID}"
echo "Case IDs loaded: $ALL_IDS"

# ── 2. Query all data via PostgreSQL ─────────────────────────────────────────
python3 << PYEOF
import subprocess, json, os

def db_query(q):
    r = subprocess.run(
        ['kubectl', 'exec', '-n', 'arkcase', 'arkcase-rdbms-0', '--',
         'psql', '-U', 'arkcase', '-d', 'arkcase', '-t', '-c', q],
        capture_output=True, text=True
    )
    return r.stdout.strip()

case_ids = {
    'case1': ${C1_ID},
    'case2': ${C2_ID},
    'case3': ${C3_ID},
    'case4': ${C4_ID},
    'case5': ${C5_ID},
    'case6': ${C6_ID}
}

all_id_list = [v for v in case_ids.values() if v]
all_ids_sql = ','.join(str(x) for x in all_id_list)

# ── Case data from DB ────────────────────────────────────────────────────────
cases_data = {}
db_rows = db_query(f"SELECT cm_complaint_id, cm_complaint_number, cm_complaint_title, cm_complaint_priority FROM acm_complaint WHERE cm_complaint_id IN ({all_ids_sql}) ORDER BY cm_complaint_id;")
db_map = {}
for line in db_rows.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 4 and parts[0].strip().isdigit():
        db_map[int(parts[0].strip())] = {
            'case_number': parts[1].strip(),
            'title': parts[2].strip(),
            'priority': parts[3].strip()
        }

# ── Assignee from DB (acm_assignment or acm_participant) ─────────────────────
# ArkCase stores assignees in acm_participant table
assignee_rows = db_query(f"SELECT cm_object_id, cm_participant_ldap_id FROM acm_participant WHERE cm_object_type='COMPLAINT' AND cm_participant_type='assignee' AND cm_object_id IN ({all_ids_sql});")
assignee_map = {}
for line in assignee_rows.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].strip().isdigit():
        assignee_map[int(parts[0].strip())] = parts[1].strip()

for label, cid in case_ids.items():
    if not cid:
        continue
    db_info = db_map.get(cid, {})
    cases_data[label] = {
        'id': cid,
        'title': db_info.get('title', ''),
        'priority': db_info.get('priority', ''),
        'assignee': assignee_map.get(cid, ''),
        'case_number': db_info.get('case_number', '')
    }

# ── Notes with QA-Q1-2026 prefix per case ───────────────────────────────────
notes_query = f"""SELECT cm_parent_object_id, cm_note_text FROM acm_note WHERE cm_parent_object_type='COMPLAINT' AND cm_parent_object_id IN ({all_ids_sql}) AND cm_note_text ILIKE '%QA-Q1-2026%';"""
notes_raw = db_query(notes_query)
notes_by_case = {}
for line in notes_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|', 1)]
    if len(parts) == 2 and parts[0].strip().isdigit():
        cid = int(parts[0].strip())
        notes_by_case.setdefault(cid, []).append(parts[1][:200])

# ── Follow-up tasks ─────────────────────────────────────────────────────────
task_count_raw = db_query("SELECT COUNT(*) FROM act_ru_task WHERE name_='Quarterly Review Follow-up';").strip()
try:
    followup_task_count = int(task_count_raw)
except:
    followup_task_count = 0

# ── Agent report file ────────────────────────────────────────────────────────
report_path = '/home/ga/Documents/reconciliation_report.json'
report_exists = os.path.exists(report_path)
report_content = None
report_created_during_task = False
task_start = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

if report_exists:
    mtime = int(os.path.getmtime(report_path))
    if mtime > task_start:
        report_created_during_task = True
    try:
        with open(report_path) as f:
            report_content = json.load(f)
    except:
        try:
            report_content = open(report_path).read()[:2000]
        except:
            report_content = None
    try:
        import shutil
        shutil.copy2(report_path, '/tmp/agent_report.json')
        os.chmod('/tmp/agent_report.json', 0o644)
    except:
        pass

# ── Copy ground truth ────────────────────────────────────────────────────────
gt_path = '/root/validation/ground_truth.json'
if os.path.exists(gt_path):
    import shutil
    shutil.copy2(gt_path, '/tmp/ground_truth.json')
    os.chmod('/tmp/ground_truth.json', 0o644)

# ── Initial counts ───────────────────────────────────────────────────────────
initial_note_count = 0
if os.path.exists('/tmp/initial_note_count'):
    try:
        initial_note_count = int(open('/tmp/initial_note_count').read().strip())
    except:
        pass

# ── Build result ─────────────────────────────────────────────────────────────
result = {
    'task_start': task_start,
    'task_end': int(subprocess.check_output(['date', '+%s']).decode().strip()),
    'cases': {},
    'notes_by_case': {str(k): v for k, v in notes_by_case.items()},
    'followup_task_count': followup_task_count,
    'initial_note_count': initial_note_count,
    'report_exists': report_exists,
    'report_created_during_task': report_created_during_task,
    'report_content': report_content,
    'screenshot_path': '/tmp/task_final.png'
}

for label, cdata in cases_data.items():
    cid = cdata['id']
    cdata['notes'] = notes_by_case.get(cid, [])
    cdata['note_count'] = len(cdata['notes'])
    result['cases'][label] = cdata

json.dump(result, open('/tmp/reconciliation_result.json', 'w'), indent=2, default=str)
print(json.dumps(result, indent=2, default=str))
PYEOF

# ── 3. Copy to standard location ────────────────────────────────────────────
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/reconciliation_result.json /tmp/task_result.json 2>/dev/null || \
    sudo cp /tmp/reconciliation_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || \
    sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
