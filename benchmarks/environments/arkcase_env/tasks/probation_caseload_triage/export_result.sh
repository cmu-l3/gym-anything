#!/bin/bash
# post_task: Export results for probation_caseload_triage
# Queries the ArkCase PostgreSQL database to capture the current state
# of the 7 probation cases and any new notes/tasks.

echo "=== Exporting probation_caseload_triage result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# DB query helper
arkcase_db() {
    kubectl exec -n arkcase arkcase-rdbms-0 -- psql -U arkcase -d arkcase -t -c "$1" 2>/dev/null
}

# Load case IDs from setup
if [ ! -f /tmp/probation_caseload_ids.json ]; then
    echo "ERROR: Setup IDs file not found"
    cat > /tmp/probation_caseload_result.json << 'EOF'
{"error": "Setup IDs file not found", "passed": false, "score": 0}
EOF
    exit 0
fi

CASE1_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['noncompliant_ids'][0])" 2>/dev/null || echo "0")
CASE2_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['noncompliant_ids'][1])" 2>/dev/null || echo "0")
CASE3_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['noncompliant_ids'][2])" 2>/dev/null || echo "0")
CASE4_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['compliant_ids'][0])" 2>/dev/null || echo "0")
CASE5_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['compliant_ids'][1])" 2>/dev/null || echo "0")
CASE6_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['compliant_ids'][2])" 2>/dev/null || echo "0")
CASE7_ID=$(python3 -c "import json; d=json.load(open('/tmp/probation_caseload_ids.json')); print(d['compliant_ids'][3])" 2>/dev/null || echo "0")

ALL_IDS="${CASE1_ID},${CASE2_ID},${CASE3_ID},${CASE4_ID},${CASE5_ID},${CASE6_ID},${CASE7_ID}"
NONCOMPLIANT_IDS="${CASE1_ID},${CASE2_ID},${CASE3_ID}"

echo "Case IDs loaded: NC=[$NONCOMPLIANT_IDS], C=[$CASE4_ID,$CASE5_ID,$CASE6_ID,$CASE7_ID]"

# Query current priority of each case
python3 << PYEOF
import subprocess, json

def db_query(q):
    r = subprocess.run(
        ['kubectl', 'exec', '-n', 'arkcase', 'arkcase-rdbms-0', '--',
         'psql', '-U', 'arkcase', '-d', 'arkcase', '-t', '-c', q],
        capture_output=True, text=True
    )
    return r.stdout.strip()

nc_ids = [int(x) for x in '${CASE1_ID},${CASE2_ID},${CASE3_ID}'.split(',') if x.strip().isdigit()]
c_ids  = [int(x) for x in '${CASE4_ID},${CASE5_ID},${CASE6_ID},${CASE7_ID}'.split(',') if x.strip().isdigit()]
all_ids = nc_ids + c_ids

if not all_ids:
    result = {"error": "No valid case IDs found"}
    json.dump(result, open('/tmp/probation_caseload_result.json','w'))
    raise SystemExit(0)

# Current priorities
priorities_raw = db_query(f"SELECT cm_complaint_id, cm_complaint_priority FROM acm_complaint WHERE cm_complaint_id IN ({','.join(str(x) for x in all_ids)}) ORDER BY cm_complaint_id;")
priorities = {}
for line in priorities_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) == 2 and parts[0].isdigit():
        priorities[int(parts[0])] = parts[1]

# Noncompliant case priorities
nc_priorities = {cid: priorities.get(cid, 'UNKNOWN') for cid in nc_ids}
# Compliant case priorities
c_priorities = {cid: priorities.get(cid, 'UNKNOWN') for cid in c_ids}

# How many non-compliant cases have been escalated to High
nc_high_count = sum(1 for p in nc_priorities.values() if p == 'High')

# How many compliant cases have been incorrectly changed
c_wrongly_changed = sum(1 for cid, p in c_priorities.items() if p == 'High')

# Notes added to non-compliant cases with required text
note_query = f"""SELECT cm_parent_object_id, cm_note_text FROM acm_note WHERE cm_parent_object_type='COMPLAINT' AND cm_parent_object_id IN ({','.join(str(x) for x in nc_ids)}) AND cm_note_text ILIKE '%NON-COMPLIANCE FLAGGED%';"""
notes_raw = db_query(note_query)
noncompliant_notes = []
for line in notes_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].isdigit():
        noncompliant_notes.append({'case_id': int(parts[0]), 'text_snippet': parts[1][:100]})

# Notes added to compliant cases (should be 0)
compliant_note_query = f"""SELECT COUNT(*) FROM acm_note WHERE cm_parent_object_type='COMPLAINT' AND cm_parent_object_id IN ({','.join(str(x) for x in c_ids)});"""
compliant_notes_count = int(db_query(compliant_note_query).strip() or '0')

# Task creation count
task_query = "SELECT id_, name_, assignee_ FROM act_ru_task WHERE name_='Schedule immediate office report';"
tasks_raw = db_query(task_query)
tasks_created = []
for line in tasks_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0]:
        tasks_created.append({'id': parts[0], 'name': parts[1] if len(parts)>1 else '', 'assignee': parts[2] if len(parts)>2 else ''})

# Initial counts from setup
initial_note_count = int(open('/tmp/initial_note_count').read().strip() or '0') if __import__('os').path.exists('/tmp/initial_note_count') else 0
initial_task_count = int(open('/tmp/initial_task_count').read().strip() or '0') if __import__('os').path.exists('/tmp/initial_task_count') else 0

result = {
    "noncompliant_ids": nc_ids,
    "compliant_ids": c_ids,
    "nc_priorities": {str(k): v for k, v in nc_priorities.items()},
    "c_priorities": {str(k): v for k, v in c_priorities.items()},
    "nc_high_count": nc_high_count,
    "c_wrongly_changed_count": c_wrongly_changed,
    "noncompliant_notes_with_text": noncompliant_notes,
    "noncompliant_notes_count": len(noncompliant_notes),
    "compliant_notes_count": compliant_notes_count,
    "tasks_created": tasks_created,
    "tasks_count": len(tasks_created),
    "initial_note_count": initial_note_count,
    "initial_task_count": initial_task_count,
    "export_timestamp": __import__('datetime').datetime.utcnow().isoformat()
}

json.dump(result, open('/tmp/probation_caseload_result.json','w'), indent=2)
print(f"Exported: nc_high={nc_high_count}/3, notes={len(noncompliant_notes)}/3, tasks={len(tasks_created)}/3, c_wrong={c_wrongly_changed}")
PYEOF

echo "=== Export complete ==="
cat /tmp/probation_caseload_result.json
