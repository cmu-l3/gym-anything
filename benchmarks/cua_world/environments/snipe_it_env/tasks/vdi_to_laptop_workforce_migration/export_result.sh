#!/bin/bash
echo "=== Exporting vdi_to_laptop_workforce_migration results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/vdi_migration_final.png

# Extract raw data to temp files
snipeit_db_query "SELECT asset_tag, assigned_to, status_id FROM assets WHERE asset_tag IN ('TC-001','TC-002','TC-003')" > /tmp/tc_states.txt
snipeit_db_query "SELECT asset_tag, assigned_to FROM assets WHERE asset_tag IN ('LAP-WFH-001','LAP-WFH-002','LAP-WFH-003')" > /tmp/lap_states.txt
snipeit_db_query "SELECT username, id, location_id FROM users WHERE username IN ('aadams','bbaker','cclark')" > /tmp/user_states.txt

ACC_ID=$(snipeit_db_query "SELECT id FROM accessories WHERE name='Jabra Evolve2 65' LIMIT 1" | tr -d '[:space:]')
if [ -n "$ACC_ID" ]; then
    snipeit_db_query "SELECT assigned_to FROM accessories_users WHERE accessory_id=$ACC_ID" > /tmp/acc_states.txt
else
    echo "" > /tmp/acc_states.txt
fi

SL_RETIRED=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Retired' LIMIT 1" | tr -d '[:space:]')
LOC_REMOTE=$(snipeit_db_query "SELECT id FROM locations WHERE name='Remote/WFH' LIMIT 1" | tr -d '[:space:]')

# Compile results securely into JSON
python3 << 'PYEOF' > /tmp/vdi_migration_result.json
import json
import os

def read_tsv(path):
    if not os.path.exists(path): return []
    try:
        with open(path, 'r') as f:
            return [line.strip().split('\t') for line in f if line.strip()]
    except Exception as e:
        return []

tc_states = read_tsv('/tmp/tc_states.txt')
lap_states = read_tsv('/tmp/lap_states.txt')
user_states = read_tsv('/tmp/user_states.txt')
acc_states = read_tsv('/tmp/acc_states.txt')

users = {u[0]: {"id": u[1], "location_id": u[2]} for u in user_states if len(u) >= 3}
tcs = {t[0]: {"assigned_to": t[1], "status_id": t[2]} for t in tc_states if len(t) >= 3}
laps = {l[0]: {"assigned_to": l[1]} for l in lap_states if len(l) >= 2}
acc_assigned = [a[0] for a in acc_states if len(a) >= 1]

result = {
    "retired_status_id": "$SL_RETIRED".strip(),
    "remote_loc_id": "$LOC_REMOTE".strip(),
    "users": users,
    "thin_clients": tcs,
    "laptops": laps,
    "headset_assigned_users": acc_assigned
}
print(json.dumps(result, indent=2))
PYEOF

echo "Result JSON written to /tmp/vdi_migration_result.json:"
cat /tmp/vdi_migration_result.json

echo "=== Export Complete ==="