#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting fiscal_year_depreciation_setup task results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Export Database Tables to TSV
echo "Exporting DB state..."
snipeit_db_query "SELECT id, name, months FROM depreciations" > /tmp/deps.tsv
snipeit_db_query "SELECT id, name, COALESCE(depreciation_id, 0) FROM models WHERE deleted_at IS NULL" > /tmp/models.tsv
snipeit_db_query "SELECT asset_tag, COALESCE(purchase_cost, 0.00), COALESCE(purchase_date, '') FROM assets WHERE asset_tag LIKE 'ASSET-DEP%' AND deleted_at IS NULL" > /tmp/assets.tsv

# 3. Process TSV to structured JSON using Python
python3 << 'PYEOF'
import json
import os

def read_tsv(path):
    if not os.path.exists(path):
        return []
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip().split('\t') for line in f if line.strip()]

deps_raw = read_tsv('/tmp/deps.tsv')
models_raw = read_tsv('/tmp/models.tsv')
assets_raw = read_tsv('/tmp/assets.tsv')

data = {
    "depreciations": [],
    "models": [],
    "assets": []
}

for row in deps_raw:
    if len(row) >= 3:
        data["depreciations"].append({
            "id": int(row[0]),
            "name": row[1],
            "months": int(row[2])
        })

for row in models_raw:
    if len(row) >= 3:
        data["models"].append({
            "id": int(row[0]),
            "name": row[1],
            "depreciation_id": int(row[2]) if row[2] != '0' else None
        })

for row in assets_raw:
    if len(row) >= 3:
        try:
            cost = float(row[1])
        except ValueError:
            cost = 0.0
        data["assets"].append({
            "tag": row[0],
            "cost": cost,
            "date": row[2]
        })

# Save securely to /tmp/task_result.json
with open('/tmp/task_result_temp.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
PYEOF

# Move file safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_temp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/task_result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_result_temp.json /tmp/deps.tsv /tmp/models.tsv /tmp/assets.tsv

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="