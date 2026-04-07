#!/bin/bash
echo "=== Exporting proxy_leave_entry_and_approval result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Dump necessary DB tables to TSV for robust programmatic verification
echo "Dumping database tables..."
# Check possible table names for leave requests
REQ_TABLE="main_leaverequest"
if ! docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "DESCRIBE $REQ_TABLE;" >/dev/null 2>&1; then
    if docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "DESCRIBE main_leaverequests;" >/dev/null 2>&1; then
        REQ_TABLE="main_leaverequests"
    fi
fi

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM $REQ_TABLE;" > /tmp/raw_requests.tsv 2>/dev/null || touch /tmp/raw_requests.tsv
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_users;" > /tmp/raw_users.tsv 2>/dev/null || touch /tmp/raw_users.tsv
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e "SELECT * FROM main_employeeleavetypes;" > /tmp/raw_types.tsv 2>/dev/null || touch /tmp/raw_types.tsv

# Convert TSV dumps to JSON using a robust Python script
python3 << 'EOF'
import csv, json, os

def tsv_to_list(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        reader = csv.DictReader(f, delimiter='\t')
        return list(reader)

users = {}
for row in tsv_to_list('/tmp/raw_users.tsv'):
    if 'id' in row and 'employeeId' in row:
        users[row['id']] = row['employeeId']

types = {}
for row in tsv_to_list('/tmp/raw_types.tsv'):
    if 'id' in row:
        types[row['id']] = row.get('leavecode', row.get('leavetype', ''))

requests = tsv_to_list('/tmp/raw_requests.tsv')
processed = []

for r in requests:
    uid = r.get('user_id', r.get('userid', ''))
    empid = users.get(uid, uid)

    tid = r.get('leavetype_id', r.get('leavetypeid', ''))
    lcode = types.get(tid, tid)

    processed.append({
        'empid': empid,
        'leavecode': lcode,
        'raw_request': r
    })

with open('/tmp/task_result.json', 'w') as f:
    json.dump({'requests': processed}, f)
EOF

# Make sure permissions are safe for verifier.py
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

# Clean up raw dumps
rm -f /tmp/raw_requests.tsv /tmp/raw_users.tsv /tmp/raw_types.tsv

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export complete ==="