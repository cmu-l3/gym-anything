#!/bin/bash
echo "=== Exporting annual_compensation_adjustment result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot as a safety backup
take_screenshot /tmp/task_final.png

# Dynamically dump DB tables to TSV (Handles any foreign key / structure quirks gracefully)
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "SELECT u.employeeId, s.* FROM main_users u JOIN main_employeesalary s ON u.id = s.user_id;" > /tmp/salaries.tsv 2>/dev/null || true
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "SELECT u.employeeId, a.* FROM main_users u JOIN main_employeeallowances a ON u.id = a.user_id;" > /tmp/allowances.tsv 2>/dev/null || true

# Parse the TSV files safely into JSON using Python
python3 << EOF
import csv, json

def tsv_to_dict(filepath):
    try:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f, delimiter='\t')
            return list(reader)
    except Exception:
        return []

data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "salaries": tsv_to_dict('/tmp/salaries.tsv'),
    "allowances": tsv_to_dict('/tmp/allowances.tsv'),
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="