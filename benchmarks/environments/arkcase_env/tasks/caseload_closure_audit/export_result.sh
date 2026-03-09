#!/bin/bash
# post_task: Export results for caseload_closure_audit

echo "=== Exporting caseload_closure_audit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

if [ ! -f /tmp/closure_audit_ids.json ]; then
    echo "ERROR: Setup IDs file not found"
    cat > /tmp/closure_audit_result.json << 'EOF'
{"error": "Setup IDs file not found", "passed": false, "score": 0}
EOF
    exit 0
fi

python3 << PYEOF
import subprocess, json

def db_query(q):
    r = subprocess.run(
        ['kubectl', 'exec', '-n', 'arkcase', 'arkcase-rdbms-0', '--',
         'psql', '-U', 'arkcase', '-d', 'arkcase', '-t', '-c', q],
        capture_output=True, text=True
    )
    return r.stdout.strip()

ids = json.load(open('/tmp/closure_audit_ids.json'))
exp_ids = [x for x in ids.get('expired_ids', []) if x > 0]
act_ids = [x for x in ids.get('active_ids', []) if x > 0]
all_ids = exp_ids + act_ids

if not all_ids:
    result = {"error": "No valid case IDs"}
    json.dump(result, open('/tmp/closure_audit_result.json', 'w'))
    raise SystemExit(0)

all_ids_str = ','.join(str(x) for x in all_ids)
exp_ids_str = ','.join(str(x) for x in exp_ids)
act_ids_str = ','.join(str(x) for x in act_ids)

# Current statuses
status_raw = db_query(
    f"SELECT cm_complaint_id, cm_complaint_status "
    f"FROM acm_complaint WHERE cm_complaint_id IN ({all_ids_str}) ORDER BY cm_complaint_id;"
)
statuses = {}
for line in status_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].isdigit():
        statuses[int(parts[0])] = parts[1]

# Expired cases closed
exp_closed_count = sum(1 for cid in exp_ids if statuses.get(cid, '') == 'Closed')
# Active cases wrongly closed
act_wrongly_closed = sum(1 for cid in act_ids if statuses.get(cid, '') == 'Closed')

# Closure notes on expired cases
note_query = (
    f"SELECT cm_parent_object_id, cm_note_text FROM acm_note "
    f"WHERE cm_parent_object_type='COMPLAINT' "
    f"AND cm_parent_object_id IN ({exp_ids_str}) "
    f"AND cm_note_text ILIKE '%CASE CLOSED%' "
    f"AND cm_note_text ILIKE '%SOP-PO-12%';"
)
notes_raw = db_query(note_query)
closure_notes = []
for line in notes_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].isdigit():
        closure_notes.append({'case_id': int(parts[0]), 'text_snippet': parts[1][:120]})

# Unique cases with proper closure note
cases_with_notes = len(set(n['case_id'] for n in closure_notes))

result = {
    "expired_ids": exp_ids,
    "active_ids": act_ids,
    "exp_statuses": {str(k): v for k, v in statuses.items() if k in exp_ids},
    "act_statuses": {str(k): v for k, v in statuses.items() if k in act_ids},
    "exp_closed_count": exp_closed_count,
    "act_wrongly_closed_count": act_wrongly_closed,
    "closure_notes": closure_notes,
    "cases_with_closure_notes": cases_with_notes,
    "export_timestamp": __import__('datetime').datetime.utcnow().isoformat()
}

json.dump(result, open('/tmp/closure_audit_result.json', 'w'), indent=2)
print(f"Exported: exp_closed={exp_closed_count}/3, notes={cases_with_notes}/3, act_wrong={act_wrongly_closed}")
PYEOF

echo "=== Export complete ==="
cat /tmp/closure_audit_result.json
