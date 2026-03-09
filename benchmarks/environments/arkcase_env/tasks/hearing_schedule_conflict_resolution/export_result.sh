#!/bin/bash
# post_task: Export results for hearing_schedule_conflict_resolution

echo "=== Exporting hearing_schedule_conflict_resolution result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Load case IDs from setup
if [ ! -f /tmp/hearing_conflict_ids.json ]; then
    echo "ERROR: Setup IDs file not found"
    cat > /tmp/hearing_conflict_result.json << 'EOF'
{"error": "Setup IDs file not found", "passed": false, "score": 0}
EOF
    exit 0
fi

python3 << PYEOF
import subprocess, json, os

def db_query(q):
    r = subprocess.run(
        ['kubectl', 'exec', '-n', 'arkcase', 'arkcase-rdbms-0', '--',
         'psql', '-U', 'arkcase', '-d', 'arkcase', '-t', '-c', q],
        capture_output=True, text=True
    )
    return r.stdout.strip()

ids = json.load(open('/tmp/hearing_conflict_ids.json'))
od_ids = [x for x in ids.get('overdue_ids', []) if x > 0]
cur_ids = [x for x in ids.get('current_ids', []) if x > 0]
all_ids = od_ids + cur_ids

if not all_ids:
    result = {"error": "No valid case IDs"}
    json.dump(result, open('/tmp/hearing_conflict_result.json','w'))
    raise SystemExit(0)

all_ids_str = ','.join(str(x) for x in all_ids)
od_ids_str = ','.join(str(x) for x in od_ids)
cur_ids_str = ','.join(str(x) for x in cur_ids)

# Current priorities and statuses
state_raw = db_query(
    f"SELECT cm_complaint_id, cm_complaint_priority, cm_complaint_status "
    f"FROM acm_complaint WHERE cm_complaint_id IN ({all_ids_str}) ORDER BY cm_complaint_id;"
)
priorities = {}
statuses = {}
for line in state_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].isdigit():
        priorities[int(parts[0])] = parts[1]
        statuses[int(parts[0])] = parts[2] if len(parts) > 2 else ''

# Overdue cases: how many set to High
od_high_count = sum(1 for cid in od_ids if priorities.get(cid, '') == 'High')
# Current cases: how many wrongly set to High
cur_wrongly_changed = sum(1 for cid in cur_ids if priorities.get(cid, '') == 'High')

# Overdue cases: how many set to In Progress
od_in_progress_count = sum(1 for cid in od_ids if statuses.get(cid, '') == 'In Progress')

# Notes on overdue cases with required text
note_query = (
    f"SELECT cm_parent_object_id, cm_note_text FROM acm_note "
    f"WHERE cm_parent_object_type='COMPLAINT' "
    f"AND cm_parent_object_id IN ({od_ids_str}) "
    f"AND cm_note_text ILIKE '%CONTINUANCE REQUIRED%';"
)
notes_raw = db_query(note_query)
overdue_notes = []
for line in notes_raw.splitlines():
    parts = [p.strip() for p in line.strip().split('|')]
    if len(parts) >= 2 and parts[0].isdigit():
        overdue_notes.append({'case_id': int(parts[0]), 'text_snippet': parts[1][:120]})

result = {
    "overdue_ids": od_ids,
    "current_ids": cur_ids,
    "od_priorities": {str(k): v for k, v in priorities.items() if k in od_ids},
    "cur_priorities": {str(k): v for k, v in priorities.items() if k in cur_ids},
    "od_statuses": {str(k): v for k, v in statuses.items() if k in od_ids},
    "od_high_count": od_high_count,
    "cur_wrongly_changed_count": cur_wrongly_changed,
    "od_in_progress_count": od_in_progress_count,
    "overdue_notes_with_text": overdue_notes,
    "overdue_notes_count": len(overdue_notes),
    "export_timestamp": __import__('datetime').datetime.utcnow().isoformat()
}

json.dump(result, open('/tmp/hearing_conflict_result.json','w'), indent=2)
print(f"Exported: od_high={od_high_count}/3, notes={len(overdue_notes)}/3, "
      f"in_progress={od_in_progress_count}/3, cur_wrong={cur_wrongly_changed}")
PYEOF

echo "=== Export complete ==="
cat /tmp/hearing_conflict_result.json
