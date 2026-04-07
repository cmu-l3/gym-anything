#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png ga

# Export table states safely into TSVs
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_employeeleaveallocations WHERE year='2026';" > /tmp/allocs_raw.tsv 2>/dev/null || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT id, employeeId FROM main_users WHERE employeeId IN ('EMP012', 'EMP013', 'EMP017', 'EMP019');" > /tmp/users_raw.tsv 2>/dev/null || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT id, leavetype FROM main_employeeleavetypes;" > /tmp/types_raw.tsv 2>/dev/null || true

# Process DB dumps via python into a single JSON
python3 << 'EOF'
import json
import csv

def read_tsv(path):
    try:
        with open(path, 'r') as f:
            reader = csv.reader(f, delimiter='\t')
            try:
                headers = next(reader)
            except StopIteration:
                return []
            headers = [h.lower() for h in headers]
            rows = []
            for row in reader:
                if len(row) == len(headers):
                    rows.append(dict(zip(headers, row)))
            return rows
    except Exception as e:
        return []

allocs = read_tsv('/tmp/allocs_raw.tsv')
users = read_tsv('/tmp/users_raw.tsv')
types = read_tsv('/tmp/types_raw.tsv')

user_map = {u['id']: u['employeeid'] for u in users if 'id' in u and 'employeeid' in u}
type_map = {t['id']: t['leavetype'] for t in types if 'id' in t and 'leavetype' in t}

allocations = []
for a in allocs:
    uid = a.get('user_id') or a.get('userid') or a.get('employee_id')
    tid = a.get('leavetype_id') or a.get('leavetypeid') or a.get('leave_type_id')
    
    empid = user_map.get(uid)
    tname = type_map.get(tid)
    
    if empid:
        days = a.get('allocated_days') or a.get('allotted_days') or a.get('total_days') or a.get('leave_days') or a.get('no_of_days') or a.get('days') or a.get('allocateddays') or "0"
        try:
            days_float = float(days)
        except:
            days_float = 0.0
        allocations.append({
            'empid': empid,
            'leavetype': tname,
            'days': days_float,
            'raw': a
        })

with open('/tmp/post_probation_result.json', 'w') as f:
    json.dump({'allocations': allocations}, f)
EOF

chmod 666 /tmp/post_probation_result.json 2>/dev/null || true
cat /tmp/post_probation_result.json
echo "=== Export complete ==="