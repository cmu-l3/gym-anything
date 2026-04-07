#!/bin/bash
echo "=== Exporting license_seat_checkout results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/license_checkout_final.png

# Query database for current seat assignments
echo "Querying license seats..."
snipeit_db_query "SELECT ls.id, ls.license_id, ls.assigned_to, u.username, l.name, UNIX_TIMESTAMP(ls.updated_at) FROM license_seats ls JOIN users u ON ls.assigned_to = u.id JOIN licenses l ON ls.license_id = l.id WHERE ls.assigned_to IS NOT NULL" > /tmp/current_seats.tsv

# Build robust JSON output using Python
python3 << 'EOF'
import json
import os

current = []
try:
    with open('/tmp/current_seats.tsv', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 6:
                current.append({
                    'id': int(parts[0]),
                    'license_id': int(parts[1]),
                    'assigned_to': int(parts[2]),
                    'username': parts[3],
                    'license_name': parts[4],
                    'updated_at': int(parts[5] if parts[5] else 0)
                })
except Exception as e:
    print(f"Error parsing current seats: {e}")

pre = []
try:
    with open('/tmp/pre_existing_seats.txt', 'r') as f:
        for line in f:
            parts = line.strip('\n').split('\t')
            if len(parts) >= 3:
                pre.append({
                    'id': int(parts[0]),
                    'license_id': int(parts[1]),
                    'assigned_to': int(parts[2])
                })
except Exception as e:
    print(f"Error parsing pre-existing seats: {e}")

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except Exception:
    task_start = 0

out = {
    'current_seats': current,
    'pre_existing_seats': pre,
    'task_start_time': task_start
}

# Write atomically via temp file
temp_path = '/tmp/task_result_temp.json'
with open(temp_path, 'w') as f:
    json.dump(out, f, indent=2)
os.rename(temp_path, '/tmp/task_result.json')
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="