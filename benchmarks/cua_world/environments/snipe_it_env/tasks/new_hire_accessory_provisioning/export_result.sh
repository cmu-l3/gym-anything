#!/bin/bash
set -e
echo "=== Exporting new_hire_accessory_provisioning results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Extract Data using an inline Python script for robust Snipe-IT API handling
python3 << 'EOF'
import json
import urllib.request
import os

def api_get(endpoint):
    try:
        with open('/home/ga/snipeit/api_token.txt', 'r') as f:
            token = f.read().strip()
        req = urllib.request.Request(
            f'http://localhost:8000/api/v1/{endpoint}', 
            headers={'Authorization': f'Bearer {token}', 'Accept': 'application/json'}
        )
        response = urllib.request.urlopen(req)
        return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"API Error on {endpoint}: {e}")
        return {"rows": []}

result = {
    "initial_accessory_count": 0,
    "final_accessory_count": 0,
    "accessories": []
}

# Get Initial Count
try:
    with open('/tmp/initial_accessory_count.txt', 'r') as f:
        result["initial_accessory_count"] = int(f.read().strip())
except:
    pass

# Fetch all accessories
acc_data = api_get('accessories?limit=100')
rows = acc_data.get('rows', [])
result["final_accessory_count"] = len(rows)

for row in rows:
    acc_id = row.get('id')
    
    # Fetch checkouts for this accessory
    co_data = api_get(f'accessories/{acc_id}/checkedout?limit=100')
    checkouts = [c.get('assigned_to', {}).get('username', '') for c in co_data.get('rows', [])]
    
    result["accessories"].append({
        "id": acc_id,
        "name": row.get('name', ''),
        "qty": row.get('qty', 0),
        "min_qty": row.get('min_qty', 0),
        "purchase_cost": row.get('purchase_cost', '0'),
        "model_number": row.get('model_number', ''),
        "category_name": row.get('category', {}).get('name', ''),
        "checked_out_to": checkouts
    })

# Write safely to temp file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results exported successfully to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="