#!/bin/bash
echo "=== Exporting dei_masterdata_config results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query Database for results
# Using -N (no column names) and -B (tab-separated batch mode)
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e \
    "SELECT prefixname FROM main_prefix WHERE prefixname IN ('Mx.', 'Prof.', 'Engr.') AND isactive=1;" > /tmp/out_prefixes.tsv 2>/dev/null

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e \
    "SELECT ethniccode, ethnicname FROM main_ethniccode WHERE ethniccode IN ('MENA', 'NHPI', 'SEA', 'MRAC') AND isactive=1;" > /tmp/out_ethnic.tsv 2>/dev/null

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e \
    "SELECT statusname FROM main_employmentstatustype WHERE statusname IN ('Seasonal Worker', 'Fellowship') AND isactive=1;" > /tmp/out_statuses.tsv 2>/dev/null

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e \
    "SELECT u.employeeId, u.firstname, u.lastname, d.deptname 
     FROM main_users u 
     LEFT JOIN main_departments d ON u.department_id = d.id 
     WHERE u.employeeId IN ('EMP021', 'EMP022') AND u.isactive=1;" > /tmp/out_employees.tsv 2>/dev/null

# Get final counts
PREFIX_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM main_prefix WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "0")
ETHNIC_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM main_ethniccode WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "0")
STATUS_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM main_employmentstatustype WHERE isactive=1;" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Process using Python into a clean JSON to avoid bash quoting nightmares
cat << 'EOF' > /tmp/process_results.py
import json
import os

def read_tsv(path):
    if not os.path.exists(path): return []
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip().split('\t') for line in f if line.strip()]

def get_file_content(path, default="0"):
    if os.path.exists(path):
        with open(path, 'r') as f:
            return f.read().strip()
    return default

prefixes = [row[0] for row in read_tsv('/tmp/out_prefixes.tsv') if len(row) >= 1]
ethnic_codes = [{"code": row[0], "name": row[1] if len(row) > 1 else ""} for row in read_tsv('/tmp/out_ethnic.tsv') if len(row) >= 1]
statuses = [row[0] for row in read_tsv('/tmp/out_statuses.tsv') if len(row) >= 1]

employees = []
for row in read_tsv('/tmp/out_employees.tsv'):
    if len(row) >= 4:
        employees.append({
            "empid": row[0],
            "firstname": row[1],
            "lastname": row[2],
            "dept": row[3]
        })

initial_counts = {
    "prefixes": int(get_file_content('/tmp/initial_prefix_count.txt')),
    "ethnic": int(get_file_content('/tmp/initial_ethnic_count.txt')),
    "statuses": int(get_file_content('/tmp/initial_status_count.txt'))
}

final_counts = {
    "prefixes": int(get_file_content('/tmp/final_prefix_count.txt', os.environ.get('PREFIX_COUNT', '0'))),
    "ethnic": int(get_file_content('/tmp/final_ethnic_count.txt', os.environ.get('ETHNIC_COUNT', '0'))),
    "statuses": int(get_file_content('/tmp/final_status_count.txt', os.environ.get('STATUS_COUNT', '0')))
}

task_start_time = int(get_file_content('/tmp/task_start_time.txt', '0'))
import time
task_end_time = int(time.time())

result = {
    "prefixes": prefixes,
    "ethnic_codes": ethnic_codes,
    "statuses": statuses,
    "employees": employees,
    "initial_counts": initial_counts,
    "final_counts": final_counts,
    "task_start_time": task_start_time,
    "task_end_time": task_end_time
}

with open('/tmp/task_result.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)
EOF

export PREFIX_COUNT ETHNIC_COUNT STATUS_COUNT
python3 /tmp/process_results.py

chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="